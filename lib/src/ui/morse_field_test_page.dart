import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/rescue_service.dart';
import '../rescue/field_test.dart';
import '../rescue/morse.dart';
import 'widgets.dart';

/// Prueba de campo: el número real, medido con la cámara y la linterna.
///
/// Se necesitan dos teléfonos. Este transmite la palabra con la linterna y la
/// pantalla; el otro la lee con el receptor. Después se marca si salió bien y
/// al final de ocho palabras queda un porcentaje que no es una simulación.
class MorseFieldTestPage extends StatefulWidget {
  const MorseFieldTestPage({super.key, this.seed});

  /// Semilla fija para las pruebas; en uso normal cambia en cada sesión.
  final int? seed;

  @override
  State<MorseFieldTestPage> createState() => _MorseFieldTestPageState();
}

class _MorseFieldTestPageState extends State<MorseFieldTestPage>
    with WidgetsBindingObserver {
  static const Color _night = Color(0xFF05090C);

  /// Ritmo normal: el mismo que usa la telegrafía y el que se lee bien a unos
  /// metros.
  static const int _unitMs = 200;

  String _level = fieldTestLevels.first;
  late List<String> _words;
  int _index = 0;
  int _correct = 0;
  bool _done = false;

  SosBlinker? _blinker;
  Timer? _endTimer;
  bool _playing = false;

  /// Si el tramo actual es de luz. Marca el fondo blanco de la pantalla, que
  /// también transmite cuando no hay linterna.
  bool _lit = false;

  bool _torchAvailable = false;
  bool _torchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _words = fieldTestWords(_level, seed: _newSeed());
    unawaited(_probeTorch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTransmission(notify: false);
    unawaited(RescueService.release());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopTransmission();
    }
  }

  int _newSeed() =>
      widget.seed ?? DateTime.now().millisecondsSinceEpoch & 0xffff;

  Future<void> _probeTorch() async {
    final available = await RescueService.hasTorch();
    if (!mounted) return;
    setState(() => _torchAvailable = available);
  }

  String get _current => _words[_index.clamp(0, _words.length - 1)];

  void _startTransmission() {
    if (_playing || _done) return;
    final message = MorseMessage.encode(_current);
    if (message.isEmpty) return;
    unawaited(RescueService.keepAwake(true));
    setState(() {
      _playing = true;
      _lit = false;
    });
    _blinker = SosBlinker(onStep: _onStep, unitMs: _unitMs, steps: message.steps)
      ..start();
    // El blinker repite para siempre: acá el mensaje se manda una vez.
    _endTimer?.cancel();
    _endTimer = Timer(message.duration(_unitMs), () {
      _stopTransmission();
    });
  }

  void _onStep(int index, LightStep step) {
    if (!mounted) return;
    setState(() {
      _lit = step.on;
    });
    if (_torchAvailable && !_torchFailed) unawaited(_driveTorch(step.on));
  }

  Future<void> _driveTorch(bool on) async {
    final ok = await RescueService.setTorch(on);
    if (!ok && on && mounted && !_torchFailed) {
      _torchFailed = true;
      setState(() => _torchAvailable = false);
      _notice(
        'La linterna no se pudo encender (¿otra app usa la cámara?). '
        'La palabra se transmite con la pantalla.',
      );
    }
  }

  Future<void> _stopTransmission({bool notify = true}) async {
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

  void _mark(bool ok) {
    if (_playing) {
      _notice('Esperá a que termine la transmisión para marcar.');
      return;
    }
    setState(() {
      if (ok) _correct++;
      if (_index + 1 >= _words.length) {
        _done = true;
      } else {
        _index++;
      }
    });
  }

  void _restart() {
    setState(() {
      _words = fieldTestWords(_level, seed: _newSeed());
      _index = 0;
      _correct = 0;
      _done = false;
      _lit = false;
      _playing = false;
    });
  }

  void _setLevel(String level) {
    if (level == _level) return;
    setState(() {
      _level = level;
      _words = fieldTestWords(level, seed: _newSeed());
      _index = 0;
      _correct = 0;
      _done = false;
    });
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: _playing && _lit ? Colors.white : _night,
      appBar: AppBar(
        title: const Text(
          'Prueba de campo',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          InfoCard(
            child: Text(
              'Con dos teléfonos: este transmite cada palabra con la linterna '
              'y la pantalla, el otro la lee con el receptor. Después marcá si '
              'salió bien. Al final tenés el número que midió tu cámara a esta '
              'distancia, no una simulación.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          _levelCard(scheme),
          const SizedBox(height: 12),
          if (!_done) _wordCard(scheme) else _resultCard(scheme),
        ],
      ),
    );
  }

  Widget _levelCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dificultad',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final level in fieldTestLevels)
                ButtonSegment<String>(value: level, label: Text(level)),
            ],
            selected: {_level},
            onSelectionChanged: (selection) => _setLevel(selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Cada prueba son $fieldTestWordCount palabras, de la más corta a '
            'la más larga. ${_torchAvailable ? 'Se transmite con la linterna y '
                  'la pantalla.' : 'Sin linterna disponible: transmite con la '
                  'pantalla.'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _wordCard(ColorScheme scheme) {
    final word = _current;
    final message = MorseMessage.encode(word);
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Palabra ${_index + 1} de ${_words.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                'Aciertos: $_correct',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              color: _night,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  word,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF16C489),
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message.preview,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _playing ? null : _startTransmission,
            icon: Icon(_playing ? Icons.graphic_eq : Icons.flash_on),
            label: Text(
              _playing ? 'Transmitiendo…' : 'Transmitir esta palabra',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ritmo: $_unitMs ms por punto. Que el otro teléfono apunte al '
            'recuadro y no se mueva mientras dura la transmisión.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _playing ? null : () => _mark(true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Leí bien'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _playing ? null : () => _mark(false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Leí mal'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultCard(ColorScheme scheme) {
    final total = _words.length;
    final percent = fieldTestPercent(_correct, total);
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resultado',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            '$_correct de $total · $percent %',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            fieldTestVerdict(percent),
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Otra prueba'),
          ),
        ],
      ),
    );
  }
}
