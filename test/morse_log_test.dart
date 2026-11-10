import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/data/state_store.dart';
import 'package:chasqui/src/power/power_policy.dart';
import 'package:chasqui/src/rescue/morse_log.dart';

void main() {
  group('historial de morse', () {
    test('un mensaje vuelve igual del guardado', () {
      final at = DateTime(2026, 3, 4, 21, 7);
      final entry = MorseLogEntry(
        text: 'SOS',
        at: at,
        marks: 9,
        unitMs: 120,
      );
      final restored = MorseLogEntry.fromJson(entry.toJson());
      expect(restored, entry);
      expect(restored?.text, 'SOS');
      expect(restored?.marks, 9);
      expect(restored?.unitMs, 120);
    });

    test('sin ritmo estimado también se guarda', () {
      final entry = MorseLogEntry(text: 'OK', at: DateTime(2026), marks: 3);
      expect(MorseLogEntry.fromJson(entry.toJson())?.unitMs, isNull);
    });

    test('una entrada rota se descarta sin romper el resto', () {
      expect(MorseLogEntry.fromJson(null), isNull);
      expect(MorseLogEntry.fromJson('texto'), isNull);
      expect(MorseLogEntry.fromJson({'t': 'SOS'}), isNull);
      expect(MorseLogEntry.fromJson({'t': '   ', 'a': 1}), isNull);
      expect(MorseLogEntry.fromJson({'t': 'SOS', 'a': 'ayer'}), isNull);
      expect(
        MorseLogEntry.fromJson({'t': 'SOS', 'a': 1, 'm': 'nueve'})?.marks,
        0,
      );
    });

    test('la hora se muestra sola si es de hoy', () {
      final entry = MorseLogEntry(text: 'SOS', at: DateTime.now(), marks: 1);
      expect(entry.whenLabel, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('de otro día se muestra con fecha', () {
      final entry = MorseLogEntry(
        text: 'SOS',
        at: DateTime.now().subtract(const Duration(days: 2)),
        marks: 1,
      );
      expect(entry.whenLabel, matches(RegExp(r'^\d{2}/\d{2} \d{2}:\d{2}$')));
    });
  });
  group('estado con historial', () {
    test('un historial con otra forma no se lleva puesto el estado', () {
      final json = AppSnapshot(
        displayName: 'Ana',
        privateKey: Uint8List(32),
        messages: const [],
        peers: const [],
        outbox: const [],
        radioMode: RadioMode.equilibrado,
        useDemo: false,
      ).toJson();
      json['morse'] = 'esto no es una lista';

      final restored = AppSnapshot.fromJson(json);
      expect(restored.morseLog, isEmpty);
      expect(restored.displayName, 'Ana');
      expect(restored.privateKey.length, 32);
    });

    test('las entradas rotas se descartan y las buenas quedan', () {
      final json = AppSnapshot(
        displayName: 'Ana',
        privateKey: Uint8List(32),
        messages: const [],
        peers: const [],
        outbox: const [],
        radioMode: RadioMode.equilibrado,
        useDemo: false,
      ).toJson();
      json['morse'] = [
        {'t': 'SOS', 'a': 1700000000000, 'm': 9},
        'basura',
        {'sin': 'texto'},
      ];

      final restored = AppSnapshot.fromJson(json);
      expect(restored.morseLog.length, 1);
      expect(restored.morseLog.single.text, 'SOS');
    });
  });

}
