import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/data/state_store.dart';
import 'package:sinred/src/power/power_policy.dart';
import 'package:sinred/src/rescue/light_calibration.dart';

void main() {
  group('calibración del receptor', () {
    test('saca los extremos con la mediana, no con el promedio', () {
      // Un fotograma con reflejo (1.0) y otro a oscuras (0.0) no mueven la
      // mediana de un fondo parejo: el promedio sí se iría al medio.
      final dark = <double>[0.1, 0.11, 0.1, 0.12, 0.1, 1.0, 0.0];
      final bright = <double>[0.9, 0.91, 0.89, 0.9, 0.92, 0.9, 0.9];
      final calibration = LightCalibration.fromSamples(dark, bright);
      expect(calibration, isNotNull);
      expect(calibration!.dark, closeTo(0.1, 1e-9));
      expect(calibration.bright, closeTo(0.9, 1e-9));
      expect(calibration.isUsable, isTrue);
    });

    test('no alcanza con muy pocas muestras', () {
      final dark = List<double>.filled(LightCalibration.minSamples - 1, 0.1);
      final bright = List<double>.filled(LightCalibration.minSamples - 1, 0.9);
      expect(LightCalibration.fromSamples(dark, bright), isNull);
    });

    test('rechaza un lugar donde la luz no se distingue del fondo', () {
      final dark = List<double>.filled(10, 0.5);
      final bright = List<double>.filled(10, 0.53);
      expect(LightCalibration.fromSamples(dark, bright), isNull);
    });

    test('los umbrales quedan entre el fondo y la luz', () {
      const calibration = LightCalibration(dark: 0.1, bright: 0.9);
      expect(calibration.range, closeTo(0.8, 1e-9));
      expect(calibration.turnOn, closeTo(0.58, 1e-9));
      expect(calibration.turnOff, closeTo(0.42, 1e-9));
      expect(calibration.turnOff < calibration.turnOn, isTrue);
    });

    test('sobrevive al guardado', () {
      const original = LightCalibration(dark: 0.13, bright: 0.77);
      final restored = LightCalibration.fromJson(original.toJson());
      expect(restored, original);
    });

    test('un guardado roto o inservible se descarta', () {
      expect(LightCalibration.fromJson(null), isNull);
      expect(LightCalibration.fromJson('nada'), isNull);
      expect(LightCalibration.fromJson({'d': 'x', 'b': 0.9}), isNull);
      expect(LightCalibration.fromJson({'d': 0.5}), isNull);
      expect(
        LightCalibration.fromJson({'d': 0.5, 'b': 0.51}),
        isNull,
        reason: 'sin diferencia no sirve para leer',
      );
    });

    test('los valores fuera de rango se recortan a 0..1', () {
      final restored = LightCalibration.fromJson({'d': -3, 'b': 4});
      expect(restored?.dark, 0);
      expect(restored?.bright, 1);
    });
  });

  group('guardado del estado', () {
    AppSnapshot snapshot(LightCalibration? calibration) => AppSnapshot(
      displayName: 'Yo',
      privateKey: Uint8List(32),
      messages: const [],
      peers: const [],
      outbox: const [],
      radioMode: RadioMode.equilibrado,
      useDemo: true,
      lightCalibration: calibration,
    );

    test('la calibración llega al archivo y vuelve', () {
      const calibration = LightCalibration(dark: 0.2, bright: 0.8);
      final json = snapshot(calibration).toJson();
      expect(json['lightCal'], {'d': 0.2, 'b': 0.8});

      final restored = AppSnapshot.fromJson(json);
      expect(restored.lightCalibration, calibration);
    });

    test('sin calibración el estado sigue cargando', () {
      final json = snapshot(null).toJson();
      expect(json.containsKey('lightCal'), isFalse);
      expect(AppSnapshot.fromJson(json).lightCalibration, isNull);
    });
  });
}
