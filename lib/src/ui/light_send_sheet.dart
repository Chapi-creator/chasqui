import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/rescue_service.dart';
import '../rescue/morse.dart';

/// Manda un texto con la linterna sin salir del chat.
///
/// Es la otra mitad de la conversación: la malla no llega, pero la luz sí. El
/// mensaje no pasa por la radio: se transmite con la linterna y la pantalla,
/// igual que en la telegrafía, así que la malla sigue escuchando mientras
/// tanto.
Future<void> showLightSendSheet(
  BuildContext context, {
  String initialText = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => LightSendSheet(initialText: initialText),
  );
}

class LightSendSheet extends StatefulWidget {
  const LightSendSheet({super.key, this.initialText = ''});

  final String initialText;

  @override
  State<LightSendSheet> createState() => _LightSendSheetState();
}

class _LightSendSheetState extends State<LightSendSheet>
    with WidgetsBindingObserver {
  static const List<int> _speeds = [300, 200, 120];
  static const Map<int, String> _speedLabels = {
    300: 'Lento',
    200: 'Normal',
    120: 'Rápido',
  };

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  MorseMessage _message = MorseMessage.encode('');
  int _unitMs = 200;

  SosBlinker? _blinker;
  Timer? _endTimer;
  bool _playing = false;
  bool _lit = false;

  bool _torchAvailable = false;
  bool _torchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateText(widget.initialText);
    unawaited(_probeTorch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(notify: false);
    unawaited(RescueService.release());
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si la app pasa a segundo plano, la linterna se quedaría encendida.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stop();
    }
  }

  Future<void> _probeTorch() async {
    final available = await RescueService.hasTorch();
    if (!mounted) return;
    setState(() => _torchAvailable = available);
  }

  void _updateText(String text) {
    setState(() => _message = MorseMessage.encode(text));
  }

  bool get _canPlay => !_message.isEmpty && !_playing;

  Future<void> _play() async {
    if (!_canPlay) return;
    await RescueService.keepAwake(true);
    if (!mounted) return;
    setState(() {
      _playing = true;
      _lit = false;
    });
    _blinker = SosBlinker(
      onStep: _onStep,
      unitMs: _unitMs,
      steps: _message.steps,
    )..start();
    // El blinker repite para siempre: acá se manda una sola vez.
    _endTimer?.cancel();
    _endTimer = Timer(_message.duration(_unitMs), _stop);
  }

  void _onStep(int index, LightStep step) {
    if (!mounted) return;
    setState(() => _lit = step.on);
    if (_torchAvailable && !_torchFailed) unawaited(_driveTorch(step.on));
  }

  Future<void> _driveTorch(bool on) async {
    final ok = await RescueService.setTorch(on);
    if (!ok && on && mounted && !_torchFailed) {
      _torchFailed = true;
      setState(() => _torchAvailable = false);
      _notice(
        'La linterna no se pudo encender (¿otra app usa la cámara?). '
        'El mensaje sale por la pantalla.',
      );
    }
  }

  Future<void> _stop({bool notify = true}) async {
    _endTimer?.cancel();
    _endTimer = null;
    _blinker?.stop();
    _blinker = null;
    await RescueService.release();
    if (!mounted) return;
    if (notify) {
      setState(() {
        _playing = false;
        _lit = false;
      });
    }
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flashlight_on_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mandar con la linterna',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'El texto sale en morse por la linterna y la pantalla, para quien '
            'está cerca y no tiene malla. No usa la radio.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            onChanged: _updateText,
            decoration: const InputDecoration(
              labelText: 'Texto a transmitir',
              hintText: 'ESTOY BIEN',
            ),
          ),
          const SizedBox(height: 10),
          if (_message.skipped.isNotEmpty)
            Text(
              'No tienen morse y quedan afuera: ${_message.skipped.join(' ')}',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          if (!_message.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message.preview,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(_message.duration(_unitMs).inMilliseconds / 1000).toStringAsFixed(1)} '
              'segundos a $_unitMs ms por punto.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
          ],
          SegmentedButton<int>(
            segments: [
              for (final speed in _speeds)
                ButtonSegment<int>(
                  value: speed,
                  label: Text(_speedLabels[speed]!),
                ),
            ],
            selected: {_unitMs},
            onSelectionChanged: _playing
                ? null
                : (selection) => setState(() => _unitMs = selection.first),
          ),
          if (_playing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _lit ? Colors.white : Colors.transparent,
                    border: Border.all(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _lit ? 'Luz' : 'Pausa',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _playing ? _stop : (_canPlay ? _play : null),
              icon: Icon(_playing ? Icons.stop : Icons.flash_on),
              label: Text(_playing ? 'Detener' : 'Transmitir'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _torchAvailable
                ? 'Usa la linterna y la pantalla al máximo: gasta batería. No '
                      'cierres la app mientras transmite.'
                : 'Este teléfono no reporta linterna: transmite con la '
                      'pantalla al máximo. Gasta batería.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
