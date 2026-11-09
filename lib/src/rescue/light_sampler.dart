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
///
/// Un cambio de estado no se acepta por un solo fotograma: tiene que sostenerse
/// [minSegmentMs]. Sin esa espera, un parpadeo de la exposición corta una raya
/// en dos y el mensaje sale sin sentido. La duración se mide desde que el
/// cambio empezó, no desde que se confirmó, así el temblor no acorta el tramo.
class LightSampler {
  LightSampler({
    this.minSegmentMs = 45,
    this.onRatio = 0.6,
    this.offRatio = 0.4,
    this.minRange = 0.04,
    this.windowMs = 6000,
  });

  /// Cuánto tiene que sostenerse un cambio para creerle.
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

  /// Estado que se está esperando confirmar, y desde cuándo.
  bool? _candidate;
  int _candidateSinceMs = 0;

  /// Última diferencia entre lo más oscuro y lo más claro de la ventana.
  double _contrast = 0;

  bool get isOn => _on;

  /// Contraste que está viendo la cámara ahora. Si es bajo, no hay nada que
  /// leer: la pantalla lo avisa en lugar de escribir basura.
  double get contrast => _contrast;

  bool get hasSignal => _contrast >= minRange;

  void reset() {
    _window.clear();
    _on = false;
    _started = false;
    _sinceMs = 0;
    _candidate = null;
    _candidateSinceMs = 0;
    _contrast = 0;
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
    _contrast = high - low;

    // Sin contraste todavía no se puede adaptar nada: pasa al principio, con
    // la luz ya encendida, cuando la ventana solo tiene brillo. Ahí se usan
    // umbrales fijos; en cuanto la luz se apaga aparece el contraste real y
    // mandan los adaptativos.
    final double turnOn;
    final double turnOff;
    if (_contrast < minRange) {
      turnOn = 0.6;
      turnOff = 0.45;
    } else {
      final range = high - low;
      turnOn = low + range * onRatio;
      turnOff = low + range * offRatio;
    }

    final wanted = _on ? value > turnOff : value > turnOn;
    if (wanted == _on) {
      _candidate = null;
      return null;
    }

    // El cambio recién empieza: se anota cuándo, sin tocar el tramo en curso.
    if (_candidate != wanted) {
      _candidate = wanted;
      _candidateSinceMs = timeMs;
      return null;
    }

    if (timeMs - _candidateSinceMs < minSegmentMs) return null;

    final duration = _candidateSinceMs - _sinceMs;
    // El tramo que termina fue un temblor, no un símbolo: no se reporta, pero
    // el reloj avanza igual. Si no avanzara, el cambio se reintentaría para
    // siempre y el receptor se quedaría trabado.
    final ended = duration >= minSegmentMs
        ? LightTransition(on: _on, ms: duration)
        : null;
    _on = wanted;
    _sinceMs = _candidateSinceMs;
    _candidate = null;
    return ended;
  }
}

class _Sample {
  const _Sample(this.value, this.ms);

  final double value;
  final int ms;
}
