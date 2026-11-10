import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/power/power_policy.dart';
import 'package:chasqui/src/power/radio_scheduler.dart';

/// Reloj controlado: la ventana se alinea con la hora del teléfono, así que en
/// los tests se fija un origen que cae justo en una frontera de todos los
/// intervalos (20, 45, 120 y 300 s dividen 1800 s).
RadioScheduler schedulerFor(FakeAsync async, {List<bool>? gates}) {
  final origin = DateTime.fromMillisecondsSinceEpoch(1800000);
  return RadioScheduler(
    onScanGate: gates?.add ?? (_) {},
    enableBatteryMonitor: false,
    now: () => origin.add(async.elapsed),
  );
}

void main() {
  test('un anuncio durante la ventana no la alarga', () {
    fakeAsync((async) {
      final gates = <bool>[];
      final scheduler = schedulerFor(async, gates: gates);
      scheduler.start();

      expect(scheduler.scanning, isTrue);
      expect(scheduler.plan.window, const Duration(seconds: 4));

      async.elapse(const Duration(seconds: 2));
      // Ráfaga de presencias: antes cada una reiniciaba el temporizador y el
      // escáner se quedaba encendido indefinidamente.
      for (var i = 0; i < 20; i++) {
        scheduler.onScanResult(found: true);
      }
      async.elapse(const Duration(seconds: 2));

      expect(
        scheduler.scanning,
        isFalse,
        reason: 'la ventana dura 4 s, no se reinicia con cada presencia',
      );
      expect(gates.last, isFalse);

      scheduler.stop();
      scheduler.dispose();
    });
  });

  test('después del descanso vuelve a escuchar', () {
    fakeAsync((async) {
      final gates = <bool>[];
      final scheduler = schedulerFor(async, gates: gates);
      scheduler.start();

      // Hay nodos cerca: un anuncio en la ventana evita el descanso largo.
      async.elapse(const Duration(seconds: 2));
      scheduler.onScanResult(found: true);
      async.elapse(const Duration(seconds: 3));
      expect(scheduler.scanning, isFalse);

      // Ventana 4 s + descanso 41 s = 45 s de ciclo.
      async.elapse(const Duration(seconds: 41));
      expect(scheduler.scanning, isTrue);

      scheduler.stop();
      scheduler.dispose();
    });
  });

  test('sin nodos cerca el descanso crece', () {
    fakeAsync((async) {
      final gates = <bool>[];
      final scheduler = schedulerFor(async, gates: gates);
      scheduler.start();
      final first = scheduler.plan.interval;

      scheduler.onScanResult(found: false);
      async.elapse(const Duration(seconds: 5));
      scheduler.onScanResult(found: false);
      async.elapse(const Duration(seconds: 60));
      scheduler.onScanResult(found: false);
      async.elapse(const Duration(seconds: 60));

      expect(scheduler.plan.interval, greaterThan(first));

      scheduler.stop();
      scheduler.dispose();
    });
  });

  test('el modo ahorro y el rápido no comparten plan', () {
    fakeAsync((async) {
      final scheduler = schedulerFor(async);
      scheduler.start();

      scheduler.setMode(RadioMode.ahorro);
      async.elapse(const Duration(seconds: 1));
      final saver = scheduler.plan;

      scheduler.setMode(RadioMode.rapido);
      async.elapse(const Duration(seconds: 1));
      final fast = scheduler.plan;

      expect(saver.dutyCycle, lessThan(fast.dutyCycle));

      scheduler.stop();
      scheduler.dispose();
    });
  });

  test('una ventana sin ver a nadie espacia la siguiente sola', () {
    fakeAsync((async) {
      final scheduler = schedulerFor(async);
      scheduler.start();
      final first = scheduler.plan.interval;

      // La ventana dura 4 s: al cerrarse no se vio ningún nodo.
      async.elapse(const Duration(seconds: 5));
      final second = scheduler.plan.interval;
      expect(
        second,
        greaterThan(first),
        reason:
            'nadie avisa de los barridos vacíos: lo detecta el planificador',
      );

      // Otro ciclo completo sin hallazgos vuelve a espaciar.
      async.elapse(second);
      expect(scheduler.plan.interval, greaterThan(second));

      scheduler.stop();
      scheduler.dispose();
    });
  });

  test('si aparece un nodo, el plan vuelve al ritmo normal', () {
    fakeAsync((async) {
      final scheduler = schedulerFor(async);
      scheduler.start();
      final baseline = scheduler.plan.interval;

      // Dos barridos seguidos sin ver a nadie: el plan se espacia.
      async.elapse(const Duration(seconds: 5));
      async.elapse(scheduler.plan.interval);
      expect(scheduler.plan.interval, greaterThan(baseline));

      // Aparece alguien: el plan vuelve al ritmo normal y se mantiene en el
      // barrido siguiente, que ya sí encuentra nodo.
      scheduler.onScanResult(found: true);
      expect(scheduler.plan.interval, baseline);

      async.elapse(const Duration(seconds: 2));
      scheduler.onScanResult(found: true);
      async.elapse(const Duration(seconds: 3));
      expect(scheduler.plan.interval, baseline);

      scheduler.stop();
      scheduler.dispose();
    });
  });

  test('dos teléfonos que arrancan en momentos distintos acaban a la vez', () {
    fakeAsync((async) {
      final first = schedulerFor(async, gates: <bool>[]);
      final second = schedulerFor(async, gates: <bool>[]);

      first.start();
      // Hay alguien en la ventana: sin esto el plan espacia el descanso a 90 s
      // por "no ver a nadie" y las dos rejillas dejarían de coincidir.
      async.elapse(const Duration(seconds: 1));
      first.onScanResult(found: true);
      async.elapse(const Duration(seconds: 9));
      // El segundo teléfono abre su app diez segundos después: su fase es
      // distinta y, sin alineación, escucharía en otro momento para siempre.
      second.start();
      async.elapse(const Duration(seconds: 1));
      second.onScanResult(found: true);
      expect(first.scanning, isFalse);
      expect(second.scanning, isTrue);

      // Ventana 4 s, intervalo 45 s: a los 45 s del origen (35 s después de
      // arrancar el segundo) los dos están en el mismo instante.
      async.elapse(const Duration(seconds: 36));
      expect(first.scanning, isTrue);
      expect(second.scanning, isTrue);

      async.elapse(const Duration(seconds: 10));
      expect(first.scanning, isFalse);
      expect(second.scanning, isFalse);

      first.stop();
      first.dispose();
      second.stop();
      second.dispose();
    });
  });
}
