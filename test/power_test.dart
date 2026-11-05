import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/power/power_policy.dart';

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
          expect(plan.window.inMilliseconds, lessThan(plan.interval.inMilliseconds));
        }
      }
    }
  });
}
