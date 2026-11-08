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

  /// ¿El mensaje arranca con la llamada de atención (VVV)?
  bool get hasAttention =>
      text == attentionCall || text.startsWith('$attentionCall ');

  /// El texto sin la llamada de atención, para leerlo de un vistazo.
  String get message =>
      hasAttention ? text.substring(attentionCall.length).trim() : text;

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
/// El ritmo del que transmite no se conoce de antemano, así que la unidad se
/// estima con las marcas más cortas recibidas: el punto es, por definición, la
/// marca más breve. Por eso el mensaje necesita al menos un punto para
/// calibrarse; uno hecho solo de rayas (`T`, `M`, `O`) se lee como puntos.
class MorseDecoder {
  MorseDecoder({this.minMarkMs = 40, this.maxUnitMs = 600});

  /// Chispazos por debajo de esto son ruido de la cámara, no morse.
  final int minMarkMs;

  /// Tope de unidad: más lento que esto ya no es una persona transmitiendo.
  final int maxUnitMs;

  final List<_Event> _events = [];

  /// Cuántos tramos se guardan como máximo. Un mensaje largo son cientos; el
  /// tope evita que la lista crezca sin fin si alguien deja la cámara mirando
  /// una lámpara fija durante una hora.
  static const int _maxEvents = 4000;

  void mark(int ms) => _add(_Event(on: true, ms: ms));

  void gap(int ms) => _add(_Event(on: false, ms: ms));

  void _add(_Event event) {
    if (event.ms <= 0) return;
    if (event.ms < minMarkMs) {
      // Un parpadeo de un fotograma: ni marca ni pausa. Si se colara como
      // marca, la calibración tomaría ese chispazo como el punto más corto y
      // todo el mensaje saldría mal.
      return;
    }
    _events.add(event);
    if (_events.length > _maxEvents) _events.removeAt(0);
  }

  void clear() => _events.clear();

  MorseReading get reading {
    if (_events.isEmpty) return MorseReading.empty;

    final unit = _unitMs();
    if (unit == null) return MorseReading.empty;

    final buffer = StringBuffer();
    final symbols = <String>[];
    var marks = 0;
    var pending = '';

    for (final event in _events) {
      if (event.on) {
        marks++;
        symbols.add(event.ms < unit * 2 ? '.' : '-');
        continue;
      }
      // Pausas: una unidad dentro de la letra, tres entre letras, siete entre
      // palabras. Los cortes se hacen con holgura porque nadie mide exacto.
      if (event.ms < unit * 2) continue;
      if (symbols.isNotEmpty) {
        _appendLetter(buffer, symbols);
        symbols.clear();
      }
      if (event.ms >= unit * 5 && buffer.isNotEmpty) {
        if (!buffer.toString().endsWith(' ')) buffer.write(' ');
      }
    }

    if (symbols.isNotEmpty) pending = symbols.join(' ');

    return MorseReading(
      text: buffer.toString().trimRight(),
      pending: pending,
      unitMs: unit,
      marks: marks,
    );
  }

  /// Unidad estimada: el punto es la marca más corta, pero una sola marca
  /// chueca no debe arruinar la escala, así que se toma un percentil bajo en
  /// lugar del mínimo exacto.
  int? _unitMs() {
    final marks = [
      for (final event in _events)
        if (event.on && event.ms >= minMarkMs) event.ms,
    ];
    if (marks.isEmpty) return null;
    marks.sort();
    final index = (marks.length * 0.2).floor().clamp(0, marks.length - 1);
    return marks[index].clamp(minMarkMs, maxUnitMs);
  }

  void _appendLetter(StringBuffer buffer, List<String> symbols) {
    buffer.write(morseSymbolFor(symbols.join()));
  }
}

class _Event {
  const _Event({required this.on, required this.ms});

  final bool on;
  final int ms;
}
