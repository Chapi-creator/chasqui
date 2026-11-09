import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/rescue_service.dart';
import '../rescue/morse.dart';
import 'widgets.dart';

/// Telegrafía: cualquier frase escrita se convierte a morse y se transmite con
/// la linterna, la pantalla y —si se quiere— un pitido.
///
/// Es el mismo motor del SOS, pero con el alfabeto completo: sirve para decir
/// "estamos bien", "necesitamos agua" o una dirección, no solo para pedir
/// auxilio. Sigue sin tocar la radio: todo ocurre en el teléfono.
class TelegraphPage extends StatefulWidget {
  const TelegraphPage({super.key});

  @override
  State<TelegraphPage> createState() => _TelegraphPageState();
}

class _TelegraphPageState extends State<TelegraphPage>
    with WidgetsBindingObserver {
  /// Fondo cuando la pantalla no está en la fase blanca. Casi negro, para que
  /// el contraste con el destello sea el máximo.
  static const Color _night = Color(0xFF05090C);

  /// Unidades por punto. La lenta se lee de lejos; la rápida, mensajes largos.
  static const List<int> _speeds = [300, 200, 120];
  static const Map<int, String> _speedLabels = {
    300: 'Lento',
    200: 'Normal',
    120: 'Rápido',
  };

  /// Mensajes que se suelen querer transmitir; un toque los carga.
  static const List<String> _examples = [
    'SOS',
    'ESTOY BIEN',
    'NECESITO AGUA',
    'VAMOS AL NORTE',
  ];

  final TextEditingController _controller = TextEditingController(text: 'SOS');
  MorseMessage _message = MorseMessage.encode('SOS');
  SosBlinker? _blinker;

  int _unitMs = 200;

  int _step = 0;
  bool _playing = false;
  bool _useTorch = true;
  bool _useScreen = true;
  bool _beep = true;
  bool _torchAvailable = false;
  bool _torchFailed = false;
  bool _toneFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probeTorch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blinker?.stop();
    _controller.dispose();
    // Apaga linterna, pitido y brillo forzado aunque se salga con atrás.
    unawaited(RescueService.release());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La app pasó a segundo plano: el blinker seguiría encendiendo la
    // linterna y gastando batería a lo bobo. Se corta hasta que vuelva.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_playing) unawaited(_stop());
    }
  }

  Future<void> _probeTorch() async {
    final available = await RescueService.hasTorch();
    if (!mounted) return;
    setState(() {
      _torchAvailable = available;
      if (!available) _useTorch = false;
    });
  }

  void _updateText(String value) {
    setState(() => _message = MorseMessage.encode(value));
  }

  void _useExample(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _updateText(text);
  }

  bool get _canPlay => !_message.isEmpty && (_useTorch || _useScreen);

  Future<void> _play() async {
    if (_playing || !_canPlay) return;
    // Brillo al máximo y pantalla sin apagarse: el mensaje tiene que poder
    // verse al sol y no cortarse a los treinta segundos.
    await RescueService.keepAwake(true);
    if (!mounted) return;
    setState(() {
      _playing = true;
      _step = 0;
    });
    _blinker = SosBlinker(
      onStep: _onStep,
      unitMs: _unitMs,
      steps: _message.steps,
    )..start();
  }

  Future<void> _stop() async {
    _blinker?.stop();
    _blinker = null;
    await RescueService.setTorch(false);
    await RescueService.setTone(false);
    await RescueService.keepAwake(false);
    if (!mounted) return;
    setState(() {
      _playing = false;
      _step = 0;
    });
  }

  void _onStep(int index, LightStep step) {
    if (!mounted) return;
    setState(() => _step = index);
    if (_useTorch && _torchAvailable) unawaited(_driveTorch(step.on));
    if (_beep) unawaited(_driveTone(step.on));
  }

  Future<void> _driveTorch(bool on) async {
    final ok = await RescueService.setTorch(on);
    // Si la linterna falló una vez (otra app con la cámara), se sigue con la
    // pantalla en lugar de reintentar en cada punto.
    if (!ok && on && mounted && !_torchFailed) {
      _torchFailed = true;
      setState(() {
        _torchAvailable = false;
        _useTorch = false;
      });
      _showNotice(
        'La linterna no se pudo encender (¿otra app usa la cámara?). '
        'El mensaje sigue con la pantalla.',
      );
    }
  }

  Future<void> _driveTone(bool on) async {
    final ok = await RescueService.setTone(on);
    if (!ok && on && mounted && !_toneFailed) {
      _toneFailed = true;
      setState(() => _beep = false);
      _showNotice('El pitido no salió: el altavoz está ocupado.');
    }
  }

  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _toggleTorch(bool value) {
    setState(() {
      _useTorch = value;
      _torchFailed = false;
    });
  }

  void _toggleScreen(bool value) => setState(() => _useScreen = value);

  void _toggleBeep(bool value) {
    setState(() {
      _beep = value;
      _toneFailed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_playing) return _buildPlayer();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Telegrafía',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _introCard(scheme),
          const SizedBox(height: 12),
          _composeCard(scheme),
          const SizedBox(height: 12),
          _optionsCard(scheme),
          const SizedBox(height: 12),
          _batteryNote(scheme),
        ],
      ),
    );
  }

  Widget _cardTitle(ColorScheme scheme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _introCard(ColorScheme scheme) {
    return InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/brand/telegrafia.png',
            width: 54,
            height: 54,
            // El emblema es decorativo: sin la imagen la pantalla sigue igual.
            errorBuilder: (context, error, stack) => Icon(
              Icons.light_mode_outlined,
              size: 40,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cualquier frase, en luz',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Escribí lo que querés decir y el teléfono lo transmite en '
                  'morse con la pantalla, la linterna y un pitido opcional. '
                  'No toca la radio: la malla sigue igual.',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composeCard(ColorScheme scheme) {
    final message = _message;
    final seconds = message.duration(_unitMs).inMilliseconds / 1000;
    final pass = seconds.toStringAsFixed(1).replaceAll('.', ',');
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.edit_note, 'Escribí el mensaje'),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            onChanged: _updateText,
            maxLength: 120,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Hola, estamos bien',
              helperText: 'Mayúsculas, números y signos. La ñ tiene su código.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in _examples)
                ActionChip(
                  label: Text(example),
                  onPressed: () => _useExample(example),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (message.isEmpty)
            Text(
              'Escribí algo para ver el morse y poder transmitirlo.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message.preview,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.5,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${message.markCount} elementos · $pass s por pasada · '
              'se repite hasta que lo pares',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (message.skipped.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Se descartan porque no tienen código morse: '
                '${message.skipped.join(' ')}',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
          if (!_useTorch && !_useScreen)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Elegí al menos una luz: sin linterna ni pantalla no hay señal.',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canPlay ? () => unawaited(_play()) : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Transmitir'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionsCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.tune, 'Cómo transmitir'),
          const SizedBox(height: 12),
          Text(
            'Velocidad',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final speed in _speeds)
                ButtonSegment<int>(
                  value: speed,
                  label: Text(_speedLabels[speed] ?? '$speed'),
                ),
            ],
            selected: {_unitMs},
            onSelectionChanged: (selection) =>
                setState(() => _unitMs = selection.first),
          ),
          const SizedBox(height: 4),
          Text(
            '$_unitMs ms por punto. Más lento se lee de más lejos; más rápido '
            'entra más mensaje en el mismo tiempo.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Linterna'),
            subtitle: Text(
              _torchAvailable
                  ? 'La de atrás, la que se ve de lejos'
                  : 'Este teléfono no reporta linterna',
            ),
            value: _useTorch,
            onChanged: _torchAvailable ? _toggleTorch : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Pantalla blanca'),
            subtitle: const Text(
              'A brillo máximo, aunque el teléfono esté en modo oscuro',
            ),
            value: _useScreen,
            onChanged: _toggleScreen,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Pitido'),
            subtitle: const Text(
              'El mismo ritmo por el altavoz, por si no miran',
            ),
            value: _beep,
            onChanged: _toggleBeep,
          ),
        ],
      ),
    );
  }

  Widget _batteryNote(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.battery_alert_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Linterna y pantalla al máximo son lo que más gasta. Para un '
              'mensaje largo, mandalo dos o tres veces y apagá: repetir con la '
              'batería cargada vale más que quedarse sin teléfono.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Pantalla completa de transmisión: blanca en los puntos y rayas, negra en
  /// las pausas. La letra que va sonando queda marcada en el mensaje.
  Widget _buildPlayer() {
    final steps = _message.steps;
    final current = _step >= 0 && _step < steps.length ? steps[_step] : null;
    final lit = _useScreen && (current?.on ?? false);
    final bg = lit ? Colors.white : _night;
    final fg = lit ? Colors.black : Colors.white;
    final letterIndex = _message.markLetter(_step);
    final element = _message.markElement(_step);
    final code = letterIndex == null ? '' : _message.codeAt(letterIndex);
    final speed = _speedLabels[_unitMs] ?? '$_unitMs ms';
    final lights = _useTorch && _useScreen
        ? 'linterna y pantalla'
        : _useScreen
        ? 'solo pantalla'
        : 'solo linterna';
    final subtitle = [speed, lights, if (_beep) 'con pitido'].join(' · ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_stop());
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.light_mode_outlined, color: fg, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Telegrafía · $subtitle',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: fg,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                for (
                                  var i = 0;
                                  i < _message.text.length;
                                  i++
                                )
                                  TextSpan(
                                    text: _message.text[i],
                                    style: i == letterIndex
                                        ? TextStyle(
                                            color: bg,
                                            backgroundColor: fg,
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: fg,
                              fontSize: 40,
                              height: 1.25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text.rich(
                            _highlightCode(code, element),
                            style: TextStyle(
                              color: fg,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: lit ? Colors.black : Colors.white,
                      foregroundColor: lit ? Colors.white : Colors.black,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => unawaited(_stop()),
                    child: const Text(
                      'Parar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Se repite hasta que lo pares. Si ya te vieron, apagalo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// El código de la letra en curso, con el elemento que está encendido
  /// subrayado para seguir el ritmo con la vista.
  TextSpan _highlightCode(String code, int? element) {
    return TextSpan(
      children: [
        for (var i = 0; i < code.length; i++)
          TextSpan(
            text: code[i],
            style: i == element
                ? const TextStyle(decoration: TextDecoration.underline)
                : null,
          ),
      ],
    );
  }
}
