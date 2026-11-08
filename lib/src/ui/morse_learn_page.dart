import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../platform/rescue_service.dart';
import '../rescue/morse.dart';
import 'widgets.dart';

/// Aprender morse dentro de la app: el abecedario completo, la palabra que
/// quieras ver y escuchar, y un juego corto para fijarlo.
///
/// Todo funciona sin internet y sin conocer morse de antes. La idea es que
/// quien nunca lo vio pueda, al menos, reconocer los destellos de un mensaje:
/// la primera letra es el nombre, la segunda el apellido.
class MorseLearnPage extends StatefulWidget {
  const MorseLearnPage({super.key, this.quizSeed});

  /// Semilla del juego. Solo la usan las pruebas, para que la pregunta salga
  /// siempre igual; en la app va null y cada partida es distinta.
  final int? quizSeed;

  @override
  State<MorseLearnPage> createState() => _MorseLearnPageState();
}

class _MorseLearnPageState extends State<MorseLearnPage>
    with WidgetsBindingObserver {
  static const Color _night = Color(0xFF05090C);
  static const List<int> _speeds = [320, 200];
  static const Map<int, String> _speedLabels = {320: 'Lento', 200: 'Normal'};

  static const List<String> _examples = [
    'SOS',
    'HOLA',
    'AGUA',
    'AYUDA',
    'ESTOY BIEN',
  ];

  final TextEditingController _practice = TextEditingController(text: 'HOLA');
  final Random _random = Random();
  final _PatternPlayer _player = _PatternPlayer();

  int _unitMs = 320;
  String _selected = 'S';
  bool _useTorch = false;
  bool _lit = false;

  MorseMessage _word = MorseMessage.encode('HOLA');
  int? _playingLetter;

  String _quizCode = '...';
  List<String> _quizOptions = const ['S', 'O', 'H', 'T'];
  String? _quizPicked;
  int _quizScore = 0;
  int _quizAsked = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.unitMs = _unitMs;
    _newQuestion();
    _probeTorch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.stop();
    unawaited(_silence());
    _practice.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nada de linterna ni pitido con la app de fondo.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopPlaying();
    }
  }

  Future<void> _probeTorch() async {
    final available = await RescueService.hasTorch();
    if (!mounted) return;
    setState(() => _useTorch = available);
  }

  Future<void> _silence() async {
    await RescueService.setTorch(false);
    await RescueService.setTone(false);
    await RescueService.keepAwake(false);
  }

  void _stopPlaying() {
    _player.stop();
    unawaited(_silence());
    if (!mounted) return;
    setState(() {
      _lit = false;
      _playingLetter = null;
    });
  }

  /// Los tramos de un solo símbolo: sus elementos con una unidad entre ellos y
  /// una pausa corta al final, para que se distinga del siguiente.
  List<LightStep> _stepsForCode(String code) {
    final steps = <LightStep>[];
    for (var i = 0; i < code.length; i++) {
      if (i > 0) steps.add(const LightStep(on: false, units: 1));
      steps.add(LightStep(on: true, units: code[i] == '-' ? 3 : 1));
    }
    steps.add(const LightStep(on: false, units: 3));
    return steps;
  }

  Future<void> _playCode(String char) async {
    final code = morseAlphabet[char];
    if (code == null) return;
    _player.stop();
    await RescueService.keepAwake(true);
    if (!mounted) return;
    setState(() {
      _selected = char;
      _playingLetter = null;
    });
    _player.play(
      _stepsForCode(code),
      unitMs: _unitMs,
      onStep: _onStep,
      onDone: () {
        if (!mounted) return;
        setState(() {
          _lit = false;
          _playingLetter = null;
        });
      },
    );
  }

  Future<void> _playWord() async {
    if (_word.isEmpty) return;
    _player.stop();
    await RescueService.keepAwake(true);
    if (!mounted) return;
    setState(() => _playingLetter = null);
    _player.play(
      _word.steps,
      unitMs: _unitMs,
      onStep: _onStep,
      onDone: () {
        if (!mounted) return;
        setState(() {
          _lit = false;
          _playingLetter = null;
        });
      },
      letterOf: _word.bodyIndex,
    );
  }

  void _onStep(int letterIndex, LightStep step) {
    if (!mounted) return;
    setState(() {
      _lit = step.on;
      if (letterIndex >= 0) _playingLetter = letterIndex;
    });
    if (_useTorch) unawaited(RescueService.setTorch(step.on));
    unawaited(RescueService.setTone(step.on));
  }

  void _setSpeed(int unit) {
    setState(() => _unitMs = unit);
    _player.unitMs = unit;
  }

  void _updateWord(String value) {
    setState(() => _word = MorseMessage.encode(value));
  }

  void _useExample(String text) {
    _practice.text = text;
    _practice.selection = TextSelection.collapsed(offset: text.length);
    _updateWord(text);
  }

  // ------------------------------------------------------------ el juego

  /// Letras y números: lo que primero se aprende. Los signos quedan en la
  /// tabla pero no en el juego, que se haría eterno.
  static final List<String> _quizPool = [
    for (final entry in morseAlphabet.entries)
      if (entry.key != 'Ñ' && RegExp(r'^[A-Z0-9]$').hasMatch(entry.key))
        entry.key,
  ];

  void _newQuestion() {
    final random = widget.quizSeed == null
        ? _random
        : Random(widget.quizSeed! + _quizAsked);
    final pool = List<String>.from(_quizPool)..shuffle(random);
    final answer = pool.first;
    final options = <String>[answer];
    for (final option in pool.skip(1)) {
      if (options.length >= 4) break;
      options.add(option);
    }
    options.shuffle(random);
    setState(() {
      _quizCode = morseAlphabet[answer] ?? '';
      _quizOptions = options;
      _quizPicked = null;
    });
  }

  String get _quizAnswer {
    for (final entry in morseAlphabet.entries) {
      if (entry.value == _quizCode) return entry.key;
    }
    return '';
  }

  void _answer(String option) {
    if (_quizPicked != null) return;
    setState(() {
      _quizPicked = option;
      _quizAsked++;
      if (option == _quizAnswer) _quizScore++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Aprender morse',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _introCard(scheme),
          const SizedBox(height: 12),
          _speedCard(scheme),
          const SizedBox(height: 12),
          _alphabetCard(scheme),
          const SizedBox(height: 12),
          _practiceCard(scheme),
          const SizedBox(height: 12),
          _quizCard(scheme),
        ],
      ),
    );
  }

  Widget _cardTitle(ColorScheme scheme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
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
            errorBuilder: (context, error, stack) =>
                Icon(Icons.school_outlined, size: 40, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El abecedario, a mano',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cada letra es un ritmo de puntos y rayas. Tocá cualquiera '
                  'para verlo y escucharlo, armá palabras y probate en el '
                  'juego. Sin internet.',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.speed, 'Ritmo de práctica'),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: [
              for (final speed in _speeds)
                ButtonSegment<int>(
                  value: speed,
                  label: Text(_speedLabels[speed] ?? '$speed'),
                ),
            ],
            selected: {_unitMs},
            onSelectionChanged: (selection) => _setSpeed(selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            '$_unitMs ms por punto. Para aprender conviene lento; los equipos '
            'de rescate suelen mandar entre 100 y 200 ms.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _alphabetCard(ColorScheme scheme) {
    final code = morseAlphabet[_selected] ?? '';
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.table_chart_outlined, 'El abecedario'),
          const SizedBox(height: 12),
          _flashBox(scheme, code),
          const SizedBox(height: 14),
          _groupLabel(scheme, 'Letras'),
          _chips(_letters, scheme),
          const SizedBox(height: 12),
          _groupLabel(scheme, 'Números'),
          _chips(_numbers, scheme),
          const SizedBox(height: 12),
          _groupLabel(scheme, 'Signos'),
          _chips(_signs, scheme),
        ],
      ),
    );
  }

  static List<String> get _letters => [
    for (final entry in morseAlphabet.entries)
      if (RegExp(r'^[A-ZÑ]$').hasMatch(entry.key)) entry.key,
  ];

  static List<String> get _numbers => [for (var i = 0; i <= 9; i++) '$i'];

  static List<String> get _signs => [
    for (final entry in morseAlphabet.entries)
      if (!RegExp(r'^[A-ZÑ0-9]$').hasMatch(entry.key)) entry.key,
  ];

  Widget _groupLabel(ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _chips(List<String> symbols, ColorScheme scheme) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final symbol in symbols)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() => _selected = symbol);
              unawaited(_playCode(symbol));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: symbol == _selected
                    ? scheme.primary.withValues(alpha: 0.18)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: symbol == _selected
                      ? scheme.primary
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    symbol,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: symbol == _selected ? scheme.primary : null,
                    ),
                  ),
                  Text(
                    morseAlphabet[symbol] ?? '',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// La letra elegida, su código y el recuadro que imita la linterna.
  Widget _flashBox(ColorScheme scheme, String code) {
    return Row(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: _lit ? Colors.white : _night,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Text(
            _selected,
            style: TextStyle(
              color: _lit ? Colors.black : const Color(0xFF16C489),
              fontSize: 52,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 28,
                  letterSpacing: 6,
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _describe(code),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => unawaited(_playCode(_selected)),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Repetir'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Raya, punto, punto" en palabras: quien nunca vio el código necesita que
  /// alguien se lo diga, no solo ver los símbolos.
  String _describe(String code) {
    if (code.isEmpty) return '';
    final parts = [
      for (final element in code.split('')) element == '-' ? 'raya' : 'punto',
    ];
    return '${parts.join(', ')}.';
  }

  Widget _practiceCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.edit_outlined, 'Armá una palabra'),
          const SizedBox(height: 10),
          TextField(
            controller: _practice,
            onChanged: _updateWord,
            maxLength: 40,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Escribí una palabra',
              helperText: 'Se muestra letra por letra y suena al tocarla.',
              border: OutlineInputBorder(),
            ),
          ),
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
          const SizedBox(height: 12),
          if (_word.isEmpty)
            Text(
              'Escribí algo para verlo en morse.',
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
              child: Wrap(
                spacing: 6,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _word.text.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _word.text[i] == ' '
                          ? null
                          : () => unawaited(_playCode(_word.text[i])),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: i == _playingLetter
                              ? scheme.primary.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _word.text[i] == ' ' ? '␣' : _word.text[i],
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              _word.codeAt(i),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                letterSpacing: 2,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _word.preview,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (_word.skipped.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Sin código morse, se saltea: ${_word.skipped.join(' ')}',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _word.isEmpty ? null : () => unawaited(_playWord()),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Escuchar la palabra'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quizCard(ColorScheme scheme) {
    final answered = _quizPicked != null;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.quiz_outlined, 'Probate'),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Aciertos: $_quizScore de $_quizAsked',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const Spacer(),
              if (answered)
                TextButton(
                  onPressed: _newQuestion,
                  child: const Text('Siguiente'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: _night,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _quizCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF16C489),
                fontFamily: 'monospace',
                fontSize: 40,
                letterSpacing: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _quizOptions)
                _quizButton(option, scheme, answered),
            ],
          ),
          if (answered) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => unawaited(_playCode(_quizAnswer)),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text('Escuchar la $_quizAnswer'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quizButton(String option, ColorScheme scheme, bool answered) {
    final correct = option == _quizAnswer;
    final picked = option == _quizPicked;
    Color? background;
    Color? border;
    if (answered && correct) {
      background = const Color(0xFF16C489).withValues(alpha: 0.22);
      border = const Color(0xFF16C489);
    } else if (answered && picked) {
      background = scheme.error.withValues(alpha: 0.18);
      border = scheme.error;
    }
    return SizedBox(
      width: 64,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          side: BorderSide(color: border ?? scheme.outlineVariant),
          padding: EdgeInsets.zero,
        ),
        onPressed: answered ? null : () => _answer(option),
        child: Text(
          option,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
    );
  }
}

/// Reproduce una lista de tramos una sola vez, a diferencia del SOS, que se
/// repite hasta que lo apaguen.
class _PatternPlayer {
  int unitMs = 200;

  Timer? _timer;
  int _index = 0;
  List<LightStep> _steps = const [];
  void Function(int index, LightStep step)? _onStep;
  void Function()? _onDone;
  int? Function(int index)? _letterOf;

  bool get running => _timer != null;

  void play(
    List<LightStep> steps, {
    required int unitMs,
    required void Function(int index, LightStep step) onStep,
    required void Function() onDone,
    int? Function(int index)? letterOf,
  }) {
    stop();
    this.unitMs = unitMs;
    _steps = steps;
    _onStep = onStep;
    _onDone = onDone;
    _letterOf = letterOf;
    _index = 0;
    _fire();
  }

  void _fire() {
    if (_index >= _steps.length) {
      stop();
      _onDone?.call();
      return;
    }
    final index = _index++;
    final step = _steps[index];
    _onStep?.call(_letterOf?.call(index) ?? -1, step);
    _timer = Timer(step.duration(unitMs), _fire);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
