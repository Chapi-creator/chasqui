/// Niveles de brillo de un lugar concreto, medidos con la luz apagada y
/// encendida.
///
/// Los umbrales fijos del detector funcionan, pero cada cámara expone distinto:
/// con una que sube mucho el brillo de noche, el "apagado" queda casi tan claro
/// como el "encendido" y el mensaje no se lee. Calibrar dos segundos en el
/// lugar —una vez con la luz apagada y otra encendida— da los dos extremos
/// reales y de ahí salen umbrales absolutos para ese teléfono y ese lugar.
class LightCalibration {
  const LightCalibration({required this.dark, required this.bright});

  /// Brillo medido con la luz apagada (el fondo).
  final double dark;

  /// Brillo medido con la luz encendida.
  final double bright;

  /// Diferencia mínima para que la calibración sirva. Por debajo, la cámara no
  /// distingue la luz del fondo y lo honesto es decirlo en vez de guardar un
  /// umbral que va a leer cualquier cosa.
  static const double minRange = 0.06;

  /// Cantidad mínima de muestras por paso: a 30 fotogramas por segundo, dos
  /// segundos dan unas 60. Menos que esto no alcanza para sacar una mediana
  /// que no dependa de un solo fotograma raro.
  static const int minSamples = 5;

  double get range => bright - dark;

  bool get isUsable => range >= minRange;

  /// Nivel a partir del cual se considera que la luz se encendió.
  double get turnOn => dark + range * 0.6;

  /// Nivel por debajo del cual se considera que se apagó.
  double get turnOff => dark + range * 0.4;

  Map<String, dynamic> toJson() => {'d': dark, 'b': bright};

  /// Devuelve null si el guardado está incompleto o no sirve: es preferible
  /// volver a los umbrales automáticos que arrancar con una calibración rota.
  static LightCalibration? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final dark = raw['d'];
    final bright = raw['b'];
    if (dark is! num || bright is! num) return null;
    final calibration = LightCalibration(
      dark: dark.toDouble().clamp(0.0, 1.0),
      bright: bright.toDouble().clamp(0.0, 1.0),
    );
    return calibration.isUsable ? calibration : null;
  }

  /// Arma la calibración con lo que se midió en los dos pasos.
  ///
  /// Usa la mediana y no el promedio: un solo fotograma con un reflejo, o el
  /// momento en que la cámara ajusta la exposición, movería un promedio y no
  /// una mediana. Devuelve null si falta diferencia o faltan muestras.
  static LightCalibration? fromSamples(
    List<double> darkSamples,
    List<double> brightSamples,
  ) {
    if (darkSamples.length < minSamples ||
        brightSamples.length < minSamples) {
      return null;
    }
    final calibration = LightCalibration(
      dark: median(darkSamples),
      bright: median(brightSamples),
    );
    return calibration.isUsable ? calibration : null;
  }

  /// Mediana de una lista de brillos; la usa la pantalla de calibración.
  static double median(List<double> values) {
    final sorted = values.map((v) => v.clamp(0.0, 1.0)).toList()..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  @override
  bool operator ==(Object other) =>
      other is LightCalibration && other.dark == dark && other.bright == bright;

  @override
  int get hashCode => Object.hash(dark, bright);

  @override
  String toString() =>
      'calibración fondo ${(dark * 100).round()}% · '
      'luz ${(bright * 100).round()}%';
}
