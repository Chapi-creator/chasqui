import 'dart:math' as math;

import 'light_calibration.dart';

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
/// Un cambio de estado se acepta en cuanto el brillo cae del lado claro de la
/// zona muerta. Antes se exigían dos fotogramas seguidos, y eso funciona a 30
/// por segundo pero no a 10 o 15: una pausa de 120 ms entre dos puntos podía
/// caer entera entre dos fotogramas, no se reportaba, y los puntos se fundían
/// en una raya (L se leía como M, la S final como T).
///
/// Lo que filtra el ruido es la zona muerta entre los dos umbrales y la
/// [minSegmentMs]: un parpadeo de exposición de un fotograma queda por debajo
/// del mínimo y no se reporta como símbolo.
///
/// La duración no se cuenta de fotograma a fotograma: el instante del cambio se
/// interpola entre las dos muestras que lo cruzan. A 10 por segundo eso quita
/// hasta 100 ms de error por tramo, que es lo que hacía que un punto midiera
/// como raya.
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

  /// Umbrales medidos en el lugar, si el usuario calibró. Mandan sobre los
  /// automáticos: la calibración es justamente lo que se hizo para no tener
  /// que adivinar el rango en cada cámara.
  LightCalibration? _calibration;

  final List<_Sample> _window = [];
  bool _on = false;
  bool _started = false;
  int _sinceMs = 0;

  /// Última muestra, para interpolar el instante exacto del cruce.
  double _prevValue = 0;
  int _prevMs = 0;
  bool _hasPrev = false;

  /// Última diferencia entre lo más oscuro y lo más claro de la ventana.
  double _contrast = 0;

  /// Últimos umbrales automáticos que se dieron por buenos. Se guardan para no
  /// recalcularlos con ventanas donde lo único que hay es ruido.
  double _autoOn = 0.6;
  double _autoOff = 0.45;

  /// Ancho mínimo de la zona muerta, en brillo. El ruido de la cámara mueve el
  /// valor unos centésimos: si los dos umbrales quedan más juntos que esto, el
  /// detector cambia de estado en cada fotograma.
  static const double _minDeadBand = 0.06;

  bool get isOn => _on;

  /// Contraste que está viendo la cámara ahora. Si es bajo, no hay nada que
  /// leer: la pantalla lo avisa en lugar de escribir basura.
  double get contrast => _contrast;

  /// Con calibración se sabe qué niveles corresponden a "apagado" y
  /// "encendido" en este lugar, así que la cámara sirve aunque en este
  /// momento el contraste sea bajo (la luz puede estar apagada ahora mismo).
  bool get hasSignal => _calibration != null || _contrast >= minRange;

  LightCalibration? get calibration => _calibration;

  /// Cambia los umbrales. Se ignora una calibración inservible en vez de
  /// dejar el detector sin señal para siempre.
  void setCalibration(LightCalibration? value) {
    _calibration = value != null && value.isUsable ? value : null;
  }

  void reset() {
    _window.clear();
    _on = false;
    _started = false;
    _sinceMs = 0;
    _prevValue = 0;
    _prevMs = 0;
    _hasPrev = false;
    _contrast = 0;
    _autoOn = 0.6;
    _autoOff = 0.45;
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

    // Con calibración los umbrales son absolutos y no dependen de la ventana.
    // Sin ella se adaptan a lo que hay en la ventana, pero solo cuando ese
    // rango es señal de verdad y no ruido de la cámara.
    final double turnOn;
    final double turnOff;
    final calibrated = _calibration;
    if (calibrated != null) {
      turnOn = calibrated.turnOn;
      turnOff = calibrated.turnOff;
    } else {
      // Con la luz quieta, dentro de la ventana no hay más que ruido de la
      // cámara: unos centésimos de rango. Si se recalculan los umbrales con
      // eso quedan tan pegados entre sí que cada fotograma cruza uno y el
      // receptor inventa marcas (un SOS se leía HOS). Solo se recalculan
      // cuando el rango es claramente más grande que el ruido; si no, valen
      // los últimos umbrales buenos (o los de fábrica al empezar).
      if (high - low >= minRange * 2.5) {
        _autoOn = low + (high - low) * onRatio;
        _autoOff = low + (high - low) * offRatio;
      }
      // Y la zona muerta nunca se achica más que el ancho mínimo: así el
      // temblor de un solo fotograma no alcanza a cruzar los dos umbrales.
      turnOn = _autoOn;
      turnOff = math.min(_autoOff, _autoOn - _minDeadBand);
    }

    final wanted = _on ? value > turnOff : value > turnOn;
    if (wanted == _on) {
      _remember(value, timeMs);
      return null;
    }

    // El cambio se acepta en el primer fotograma que cruza el umbral. Con una
    // pausa de 120 ms a 15 fotogramas por segundo puede haber **un solo**
    // fotograma apagado; pedir dos lo borraba y pegaba los dos puntos en una
    // raya. La zona muerta entre los dos umbrales y la duración mínima ya
    // filtran el temblor.

    // El borde se interpola entre la muestra anterior y esta: a 10 fotogramas
    // por segundo, tomar el fotograma entero como borde inventa hasta 100 ms.
    //
    // Se interpola en la mitad del rango, no en el umbral de conexión: la
    // exposición automática tarda unos milisegundos en seguir al cambio, y
    // cruzar el umbral de apagado (40 % del rango) pasa más tarde que el cambio
    // real. Medido en la mitad, todos los bordes se retrasan parecido y las
    // pausas no se acortan de más (era lo que dejaba las pausas en media
    // unidad y pegaba dos puntos en una raya).
    final edge = _crossing(
      threshold: low + (high - low) * 0.5,
      ms: timeMs,
      value: value,
    );
    final duration = edge - _sinceMs;
    // El tramo que termina fue un temblor, no un símbolo: no se reporta, pero
    // el reloj avanza igual. Si no avanzara, el cambio se reintentaría para
    // siempre y el receptor se quedaría trabado.
    final ended = duration >= minSegmentMs
        ? LightTransition(on: _on, ms: duration)
        : null;
    _on = wanted;
    _sinceMs = edge;
    _remember(value, timeMs);
    return ended;
  }

  void _remember(double value, int timeMs) {
    _prevValue = value;
    _prevMs = timeMs;
    _hasPrev = true;
  }

  /// Instante en que el brillo cruzó [threshold], interpolado entre las dos
  /// muestras que lo rodean. Si la muestra anterior ya estaba del otro lado
  /// (el cambio se confirmó con retraso), el borde es el fotograma anterior.
  int _crossing({
    required double threshold,
    required int ms,
    required double value,
  }) {
    if (!_hasPrev || _prevMs >= ms) return ms;
    final span = value - _prevValue;
    if (span.abs() < 1e-6) return ms;
    final ratio = ((threshold - _prevValue) / span).clamp(0.0, 1.0);
    return _prevMs + (ratio * (ms - _prevMs)).round();
  }
}

class _Sample {
  const _Sample(this.value, this.ms);

  final double value;
  final int ms;
}
