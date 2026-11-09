import 'dart:math' as math;

import 'morse.dart';

/// Una lectura del receptor: lo que ya se puede leer y lo que está entrando.
class MorseReading {
  const MorseReading({
    required this.text,
    required this.pending,
    required this.unitMs,
    required this.marks,
  });

  /// Letras ya cerradas. Los espacios separan palabras.
  final String text;

  /// Símbolos de la letra que se está recibiendo, separados: `. -`.
  final String pending;

  /// Unidad estimada en milisegundos, o null si todavía no hay con qué.
  final int? unitMs;

  /// Marcas de luz recibidas desde el último borrado.
  final int marks;

  bool get isEmpty => text.isEmpty && pending.isEmpty;

  /// Lo que se muestra en pantalla mientras llega el mensaje.
  String get display => pending.isEmpty ? text : '$text $pending'.trim();

  static const MorseReading empty = MorseReading(
    text: '',
    pending: '',
    unitMs: null,
    marks: 0,
  );
}

/// Traduce destellos a texto: recibe duraciones de encendido y apagado y
/// devuelve el mensaje.
///
/// No tiene reloj propio ni temporizadores: así se puede probar con tiempos
/// inventados, sin cámara y sin teléfono. La cámara (o el dedo, en el modo por
/// toques) solo le pasa cuánto duró cada tramo.
///
/// El ritmo del que transmite no se conoce de antemano. En vez de creerle a la
/// marca más corta —que un solo temblor arruina— se prueban ritmos candidatos y
/// se queda con el que mejor explica todo lo recibido: las marcas tienen que
/// caer en 1 o 3 unidades (punto o raya) y las pausas en 1, 3 o 7. El ritmo
/// elegido queda fijo mientras siga explicando bien el mensaje, para que el
/// texto ya escrito no se reescriba solo.
class MorseDecoder {
  MorseDecoder({this.minMarkMs = 40, this.minUnitMs = 40, this.maxUnitMs = 800});

  /// Chispazos por debajo de esto son ruido de la cámara, no morse.
  final int minMarkMs;

  /// Ritmos fuera de este rango ya no son una persona transmitiendo.
  final int minUnitMs;
  final int maxUnitMs;

  final List<_Event> _events = [];

  /// Cuántos tramos se guardan como máximo. Un mensaje largo son cientos; el
  /// tope evita que la lista crezca sin fin si alguien deja la cámara mirando
  /// una lámpara fija durante una hora.
  static const int _maxEvents = 4000;

  /// Cuántos tramos recientes se miran para estimar el ritmo.
  static const int _estimateWindow = 400;

  int? _unit;
  MorseReading? _cached;

  void mark(int ms) {
    if (ms < minMarkMs) return;
    // Dos marcas seguidas sin pausa en el medio (la cámara no siempre reporta
    // el apagado) son en realidad una sola marca más larga.
    if (_events.isNotEmpty && _events.last.on) {
      final merged = _events.removeLast();
      _events.add(_Event(on: true, ms: merged.ms + ms));
    } else {
      _events.add(_Event(on: true, ms: ms));
    }
    _trim();
  }

  void gap(int ms) {
    if (ms < 20) return;
    if (_events.isEmpty) return; // una espera antes de la primera marca no dice nada
    if (!_events.last.on) {
      final merged = _events.removeLast();
      _events.add(_Event(on: false, ms: merged.ms + ms));
    } else {
      _events.add(_Event(on: false, ms: ms));
    }
    _trim();
  }

  void _trim() {
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
    _cached = null;
  }

  /// El silencio ya dura más que una pausa de letra (o de palabra): cierra la
  /// letra en curso. Sin esto, la última letra del mensaje se quedaría como
  /// "en curso" para siempre, porque después de ella no llega ninguna marca
  /// que la termine.
  void closeLetter({bool word = false}) {
    if (_events.isEmpty || !_events.last.on) return;
    final unit = _unit ?? reading.unitMs;
    if (unit == null) return;
    _events.add(_Event(on: false, ms: (unit * (word ? 7 : 3)).round()));
    _trim();
  }

  void clear() {
    _events.clear();
    _unit = null;
    _cached = null;
  }

  MorseReading get reading {
    final cached = _cached;
    if (cached != null) return cached;
    return _cached = _decode();
  }

  MorseReading _decode() {
    if (_events.isEmpty) return MorseReading.empty;

    // Antes de medir nada: fuera los parpadeos de un fotograma, que dejan dos
    // marcas pegadas donde hay una sola raya.
    final base = _mergeFlicker(_events);
    final unit = _estimateUnit(base);
    if (unit == null) return MorseReading.empty;

    final condensed = _condense(base, unit);
    final buffer = StringBuffer();
    final symbols = <String>[];
    var marks = 0;
    var pending = '';

    // Fronteras del modelo: punto/raya a 1,73 unidades (media geométrica entre
    // 1 y 3); pausa de letra a 4,58 (entre 3 y 7); más allá, palabra.
    final dotMax = unit * 1.73;
    final letterGap = unit * 4.58;

    for (final event in condensed) {
      if (event.on) {
        marks++;
        symbols.add(event.ms < dotMax ? '.' : '-');
        continue;
      }
      // Pausa corta: sigue la misma letra.
      if (event.ms < dotMax) continue;
      if (symbols.isNotEmpty) {
        buffer.write(morseSymbolFor(symbols.join()));
        symbols.clear();
      }
      if (event.ms >= letterGap && buffer.isNotEmpty) {
        if (!buffer.toString().endsWith(' ')) buffer.write(' ');
      }
    }

    if (symbols.isNotEmpty) pending = symbols.join(' ');

    return MorseReading(
      text: buffer.toString().replaceAll(RegExp(r' +'), ' ').trim(),
      pending: pending,
      unitMs: unit,
      marks: marks,
    );
  }

  /// Descarta las pausas de uno o dos fotogramas y une las marcas que dejan
  /// atrás.
  List<_Event> _mergeFlicker(List<_Event> events) {
    final out = <_Event>[];
    for (final event in events) {
      if (!event.on && event.ms < 60) continue;
      if (event.on && out.isNotEmpty && out.last.on) {
        out[out.length - 1] = _Event(on: true, ms: out.last.ms + event.ms);
        continue;
      }
      out.add(event);
    }
    return out;
  }

  /// Une marcas separadas por una pausa imposible (más corta que media
  /// unidad): es un parpadeo de la cámara dentro de la misma raya, no dos
  /// símbolos.
  List<_Event> _condense(List<_Event> base, int unit) {
    final out = <_Event>[];
    for (final event in base) {
      if (event.on) {
        out.add(event);
        continue;
      }
      if (out.isNotEmpty && out.last.on && event.ms < unit * 0.55) {
        // Se descarta la pausa: la próxima marca se suma a la anterior.
        continue;
      }
      out.add(event);
    }
    // Con las pausas cortas descartadas, quedan marcas pegadas: se fusionan.
    final merged = <_Event>[];
    for (final event in out) {
      if (event.on && merged.isNotEmpty && merged.last.on) {
        merged[merged.length - 1] = _Event(
          on: true,
          ms: merged.last.ms + event.ms,
        );
      } else {
        merged.add(event);
      }
    }
    return merged;
  }

  /// Ritmo que mejor explica lo recibido. Se prueban candidatos sacados de las
  /// propias duraciones (cada marca y cada pausa divididas por 1, 3 o 7) y se
  /// puntúa qué tan lejos queda cada tramo del modelo.
  int? _estimateUnit(List<_Event> base) {
    final marks = <int>[];
    final gaps = <int>[];
    for (final event in base) {
      if (event.on) {
        if (marks.length < _estimateWindow) marks.add(event.ms);
      } else if (marks.isNotEmpty && gaps.length < _estimateWindow) {
        gaps.add(event.ms);
      }
    }
    if (marks.isEmpty) return null;

    final candidates = <int>{};
    void addCandidate(num value) {
      if (value < minUnitMs || value > maxUnitMs) return;
      candidates.add((value / 5).round() * 5);
    }

    for (final mark in marks) {
      addCandidate(mark);
      addCandidate(mark / 3);
    }
    for (final gap in gaps) {
      addCandidate(gap);
      addCandidate(gap / 3);
      addCandidate(gap / 7);
    }

    var bestUnit = 0;
    var bestScore = double.infinity;
    for (final unit in candidates) {
      final score = _scoreUnit(unit, marks, gaps);
      // A igualdad de puntaje gana el ritmo más lento: el punto es la marca
      // corta, así que lo prudente es no tomar una raya como punto.
      if (score < bestScore || (score == bestScore && unit > bestUnit)) {
        bestScore = score;
        bestUnit = unit;
      }
    }
    if (bestUnit == 0) return null;

    final chosen = _unit;
    if (chosen != null && chosen != bestUnit) {
      // Cambiar de ritmo reescribe lo ya leído: solo se hace si el nuevo
      // explica bastante mejor el mensaje.
      final chosenScore = _scoreUnit(chosen, marks, gaps);
      if (bestScore > chosenScore * 0.8) return chosen;
    }
    _unit = bestUnit;
    return bestUnit;
  }

  double _scoreUnit(int unit, List<int> marks, List<int> gaps) {
    var total = 0.0;
    var count = 0;
    for (final mark in marks) {
      final a = (math.log(mark / unit)).abs();
      final b = (math.log(mark / (unit * 3))).abs();
      total += math.min(a, b);
      count++;
    }
    for (final gap in gaps) {
      var best = double.infinity;
      for (final k in const [1, 3, 7]) {
        final distance = (math.log(gap / (unit * k))).abs();
        if (distance < best) best = distance;
      }
      total += best;
      count++;
    }
    return count == 0 ? double.infinity : total / count;
  }
}

class _Event {
  const _Event({required this.on, required this.ms});

  final bool on;
  final int ms;
}
