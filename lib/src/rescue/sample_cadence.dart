import 'light_calibration.dart';

/// Cada cuánto se mira un fotograma de la cámara.
///
/// Mirar 30 fotogramas por segundo es lo que hace falta para un punto de
/// 120 ms, pero el resto del tiempo no hay nada que leer y cada fotograma
/// cuesta batería. Entonces, después de unos segundos sin ningún destello, se
/// mira uno de cada 50 ms (20 por segundo) y se vuelve al ritmo rápido apenas
/// aparece luz.
///
/// El regreso tiene que ser inmediato: si se esperara a "confirmar" el
/// destello, el segundo fotograma llegaría tarde y el punto se perdería.
class SampleCadence {
  SampleCadence({
    this.activeStepMs = 33,
    this.idleStepMs = 50,
    this.idleAfterMs = 8000,
  });

  /// Separación entre fotogramas cuando se está leyendo.
  final int activeStepMs;

  /// Separación entre fotogramas cuando no hay nada que leer.
  ///
  /// No baja más: con 120 ms por punto, a 50 ms todavía entran dos fotogramas
  /// seguidos y el detector puede confirmar el cambio.
  final int idleStepMs;

  /// Cuánto silencio hace falta para bajar el ritmo.
  final int idleAfterMs;

  int _lastActivityMs = 0;
  bool _started = false;

  /// Arranca el reloj: sin esto la pantalla estaría "en ahorro" desde el
  /// primer fotograma y perdería el primer punto.
  void start(int nowMs) {
    _started = true;
    _lastActivityMs = nowMs;
  }

  void noteActivity(int nowMs) {
    _started = true;
    _lastActivityMs = nowMs;
  }

  bool isIdle(int nowMs) =>
      _started && nowMs - _lastActivityMs >= idleAfterMs;

  int stepMs(int nowMs) => isIdle(nowMs) ? idleStepMs : activeStepMs;

  /// Un brillo alto es actividad aunque todavía no se haya confirmado el
  /// cambio: es el primer fotograma del destello.
  void observeLuma(double luma, int nowMs, LightCalibration? calibration) {
    final threshold = calibration?.turnOff ?? 0.45;
    if (luma > threshold) noteActivity(nowMs);
  }
}
