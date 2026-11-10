import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/rescue/light_calibration.dart';
import 'package:chasqui/src/rescue/sample_cadence.dart';

void main() {
  group('cadencia del receptor', () {
    test('arranca al ritmo rápido, no en ahorro', () {
      final cadence = SampleCadence();
      cadence.start(0);
      expect(cadence.isIdle(0), isFalse);
      expect(cadence.stepMs(0), cadence.activeStepMs);
      expect(cadence.stepMs(7999), cadence.activeStepMs);
    });

    test('sin destellos baja el ritmo', () {
      final cadence = SampleCadence();
      cadence.start(0);
      expect(cadence.isIdle(8000), isTrue);
      expect(cadence.stepMs(8000), cadence.idleStepMs);
    });

    test('un destello devuelve el ritmo rápido en el acto', () {
      final cadence = SampleCadence();
      cadence.start(0);
      expect(cadence.stepMs(9000), cadence.idleStepMs);
      // Primer fotograma con luz: todavía no está confirmado el cambio, pero
      // ya cuenta como actividad.
      cadence.observeLuma(0.9, 9030, null);
      expect(cadence.stepMs(9030), cadence.activeStepMs);
    });

    test('un brillo bajo no despierta la cadencia', () {
      final cadence = SampleCadence();
      cadence.start(0);
      cadence.observeLuma(0.1, 9000, null);
      expect(cadence.stepMs(9000), cadence.idleStepMs);
    });

    test('con calibración manda el umbral del lugar', () {
      final cadence = SampleCadence();
      cadence.start(0);
      // Un 0.5 no es luz con los umbrales fijos (0.45 sí, es mayor: se usa el
      // umbral calibrado para no despertar por un fondo claro).
      cadence.observeLuma(0.5, 9000, null);
      expect(cadence.stepMs(9000), cadence.activeStepMs);

      cadence.start(0);
      cadence.observeLuma(
        0.5,
        9000,
        const LightCalibration(dark: 0.55, bright: 0.9),
      );
      expect(cadence.stepMs(9000), cadence.idleStepMs);
    });

    test('el ahorro no pierde puntos de 120 ms', () {
      final cadence = SampleCadence();
      cadence.start(0);
      cadence.isIdle(9000);
      // A 50 ms entran al menos dos fotogramas en un punto de 120 ms: el
      // detector pide dos muestras seguidas para confirmar el cambio.
      expect(cadence.idleStepMs * 2, lessThanOrEqualTo(120));
    });
  });
}
