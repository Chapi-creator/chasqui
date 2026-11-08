/// Un tramo de luz que acaba de terminar: encendido o apagado, y cuánto duró.
class LightTransition {
  const LightTransition({required this.on, required this.ms});

  final bool on;
  final int ms;

  @override
  String toString() => '${on ? 'luz' : 'pausa'} $ms ms';
}

/// Convierte el brillo que ve la cámara en encendidos y apagados.
///
/// La cámara no entrega "luz sí / luz no": entrega un brillo que cambia con el
/// sol, la distancia y el ajuste automático de exposición. Por eso los umbrales
/// no son fijos: se calculan sobre el mínimo y el máximo de los últimos
/// segundos, con dos umbrales distintos (histéresis) para que un parpadeo de
/// ruido no cuente como un punto.
class LightSampler {
  LightSampler({
    this.minSegmentMs = 40,
    this.onRatio = 0.62,
    this.offRatio = 0.38,
    this.minRange = 0.05,
    this.windowMs = 8000,
  });

  /// Un cambio más corto que esto es ruido de la cámara, no morse.
  final int minSegmentMs;

  /// Brillo (relativo al rango reciente) que hace falta para pasar a "luz".
  final double onRatio;

  /// Por debajo de esto se vuelve a "apagado". Entre los dos umbrales no se
  /// cambia nada: esa zona muerta es la que evita el temblor.
  final double offRatio;

  /// Diferencia mínima entre lo más oscuro y lo más claro para creer que hay
  /// una linterna parpadeando y no una pared.
  final double minRange;

  /// Cuánto pasado se mira para calcular los umbrales.
  final int windowMs;

  final List<_Sample> _window = [];
  bool _on = false;
  bool _started = false;
  int _sinceMs = 0;

  bool get isOn => _on;

  void reset() {
    _window.clear();
    _on = false;
    _started = false;
    _sinceMs = 0;
  }

  /// Agrega una muestra de brillo (0 = negro, 1 = blanco) con su marca de
  /// tiempo. Devuelve el tramo que se cerró, o null si no cambió nada.
  LightTransition? addSample(double luma, int timeMs) {
    final value = luma.clamp(0.0, 1.0);
    _window.add(_Sample(value, timeMs));
    _window.removeWhere((sample) => timeMs - sample.ms > windowMs);

    if (!_started) {
      _started = true;
      _sinceMs = timeMs;
    }

    var low = 1.0;
    var high = 0.0;
    for (final sample in _window) {
      if (sample.value < low) low = sample.value;
      if (sample.value > high) high = sample.value;
    }
    if (high - low < minRange) return null;

    final range = high - low;
    final turnOn = low + range * onRatio;
    final turnOff = low + range * offRatio;

    final wanted = _on ? value > turnOff : value > turnOn;
    if (wanted == _on) return null;

    final duration = timeMs - _sinceMs;
    if (duration < minSegmentMs) {
      // Demasiado corto para ser morse: se descarta el intento y el reloj
      // sigue desde el mismo estado, como si el destello no hubiera existido.
      _sinceMs = timeMs;
      return null;
    }

    final ended = LightTransition(on: _on, ms: duration);
    _on = wanted;
    _sinceMs = timeMs;
    return ended;
  }
}

class _Sample {
  const _Sample(this.value, this.ms);

  final double value;
  final int ms;
}
