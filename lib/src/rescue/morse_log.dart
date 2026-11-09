/// Un mensaje leído del aire y guardado.
///
/// Se guarda el texto con la hora y con lo que el receptor sabía de la lectura
/// (marcas y ritmo): si después hay que reconstruir qué llegó y con qué
/// calidad, esa información es la única que existe.
class MorseLogEntry {
  const MorseLogEntry({
    required this.text,
    required this.at,
    required this.marks,
    this.unitMs,
  });

  final String text;
  final DateTime at;

  /// Cantidad de marcas que tenía el mensaje al cerrarse.
  final int marks;

  /// Ritmo estimado, en milisegundos por punto.
  final int? unitMs;

  Map<String, dynamic> toJson() => {
    't': text,
    'a': at.millisecondsSinceEpoch,
    'm': marks,
    if (unitMs != null) 'u': unitMs,
  };

  /// Descarta entradas rotas en vez de romper todo el estado guardado.
  static MorseLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['t'];
    final at = raw['a'];
    if (text is! String || text.trim().isEmpty || at is! num) return null;
    final unit = raw['u'];
    return MorseLogEntry(
      text: text,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      marks: raw['m'] is num ? (raw['m'] as num).toInt() : 0,
      unitMs: unit is num ? unit.toInt() : null,
    );
  }

  /// Hora y, si no es de hoy, la fecha: dos mensajes iguales de días distintos
  /// no se tienen que confundir.
  String get whenLabel {
    final now = DateTime.now();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final sameDay = at.year == now.year && at.month == now.month &&
        at.day == now.day;
    if (sameDay) return time;
    return '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')} $time';
  }

  @override
  bool operator ==(Object other) =>
      other is MorseLogEntry &&
      other.text == text &&
      other.at == at &&
      other.marks == marks &&
      other.unitMs == unitMs;

  @override
  int get hashCode => Object.hash(text, at, marks, unitMs);

  @override
  String toString() => '$text ($whenLabel)';
}
