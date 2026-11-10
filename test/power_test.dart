import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/power/power_policy.dart';

void main() {
  const policy = PowerPolicy();

  test('el modo ahorro escucha menos que el rápido', () {
    final saver = policy.plan(
      mode: RadioMode.ahorro,
      batteryLevel: 80,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );
    final fast = policy.plan(
      mode: RadioMode.rapido,
      batteryLevel: 80,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );

    expect(saver.dutyCycle, lessThan(fast.dutyCycle));
    expect(saver.interval, greaterThan(fast.interval));
  });

  test('no encontrar nodos espacia las ventanas', () {
    final fresh = policy.plan(
      mode: RadioMode.equilibrado,
      batteryLevel: 80,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );
    final lonely = policy.plan(
      mode: RadioMode.equilibrado,
      batteryLevel: 80,
      charging: false,
      emptyStreak: 4,
      hasLinks: false,
    );

    expect(lonely.interval, greaterThan(fresh.interval));
  });

  test('con batería baja alarga el descanso', () {
    final normal = policy.plan(
      mode: RadioMode.equilibrado,
      batteryLevel: 80,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );
    final low = policy.plan(
      mode: RadioMode.equilibrado,
      batteryLevel: 10,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );

    expect(low.interval, greaterThan(normal.interval));
    expect(low.window, lessThan(normal.window));
  });

  test('cargando se vuelve agresivo', () {
    final charging = policy.plan(
      mode: RadioMode.ahorro,
      batteryLevel: 5,
      charging: true,
      emptyStreak: 5,
      hasLinks: true,
    );

    expect(charging.interval, const Duration(seconds: 15));
    expect(charging.window.inSeconds, greaterThanOrEqualTo(5));
  });

  test('con enlaces abiertos se escanea menos', () {
    final alone = policy.plan(
      mode: RadioMode.equilibrado,
      batteryLevel: 70,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );
    final linked = policy.plan(
      mode: RadioMode.equilibrado,
      batteryLevel: 70,
      charging: false,
      emptyStreak: 0,
      hasLinks: true,
    );

    expect(linked.dutyCycle, lessThan(alone.dutyCycle));
  });

  test('los límites se respetan incluso en el peor caso', () {
    for (final mode in RadioMode.values) {
      for (final battery in [1, 15, 50, 100]) {
        for (final links in [true, false]) {
          final plan = policy.plan(
            mode: mode,
            batteryLevel: battery,
            charging: false,
            emptyStreak: 5,
            hasLinks: links,
          );
          expect(plan.interval.inSeconds, lessThanOrEqualTo(300));
          expect(plan.interval.inSeconds, greaterThanOrEqualTo(10));
          expect(
            plan.window.inMilliseconds,
            lessThan(plan.interval.inMilliseconds),
          );
        }
      }
    }
  });

  test('el modo supervivencia es el que menos radio usa', () {
    ScanPlan plan(RadioMode mode) => policy.plan(
      mode: mode,
      batteryLevel: 80,
      charging: false,
      emptyStreak: 0,
      hasLinks: false,
    );

    final survival = plan(RadioMode.supervivencia);
    final saver = plan(RadioMode.ahorro);

    expect(survival.dutyCycle, lessThan(saver.dutyCycle));
    expect(survival.dutyCycle, lessThan(0.02));
    expect(survival.window, const Duration(seconds: 4));
    expect(survival.interval, const Duration(minutes: 5));
  });

  test('con la batería al 5 % se pasa a la rejilla de 5 minutos', () {
    for (final mode in RadioMode.values) {
      final critical = policy.plan(
        mode: mode,
        batteryLevel: 5,
        charging: false,
        emptyStreak: 0,
        hasLinks: false,
      );
      expect(critical.interval, const Duration(minutes: 5), reason: '$mode');
      expect(critical.window, const Duration(seconds: 4));
    }

    // Cargando no hace falta tanta tacañería.
    final charging = policy.plan(
      mode: RadioMode.rapido,
      batteryLevel: 5,
      charging: true,
      emptyStreak: 0,
      hasLinks: false,
    );
    expect(charging.interval, lessThan(const Duration(minutes: 5)));
  });

  test('las ventanas caen en fronteras del reloj, no donde arrancó la app', () {
    const plan = ScanPlan(Duration(seconds: 4), Duration(minutes: 5));
    final base = DateTime.fromMillisecondsSinceEpoch(1800000);

    for (final offset in [0, 700, 123456, 299000]) {
      final now = base.add(Duration(milliseconds: offset));
      final wait = plan.delayUntilNextWindow(now);
      final next = now.add(wait);

      expect(
        next.millisecondsSinceEpoch % plan.interval.inMilliseconds,
        0,
        reason: 'offset $offset',
      );
      expect(wait, greaterThanOrEqualTo(ScanPlan.minRest));
    }
  });
}
