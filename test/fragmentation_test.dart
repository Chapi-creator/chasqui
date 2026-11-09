import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/transport/ble/fragmentation.dart';

Uint8List frame(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 7) % 256));

void main() {
  group('trozos BLE', () {
    test('un mensaje corto se reensambla igual', () {
      final original = frame(40);
      final chunks = FrameChunker.split(original, 180);
      expect(chunks.length, 1);

      final reassembler = FrameReassembler();
      final result = reassembler.add('link-1', chunks.first);
      expect(result, original);
    });

    test('trozos fuera de orden se juntan bien', () {
      final original = frame(1000);
      final chunks = FrameChunker.split(original, 100);
      expect(chunks.length, greaterThan(2));

      final reassembler = FrameReassembler();
      Uint8List? result;
      for (final chunk in chunks.reversed) {
        result = reassembler.add('link-1', chunk) ?? result;
      }
      expect(result, original);
    });

    test('dos enlaces no se mezclan aunque compartan tag', () {
      final a = frame(500);
      final b = frame(700);
      final chunksA = FrameChunker.split(a, 100);
      final chunksB = FrameChunker.split(b, 100);

      final reassembler = FrameReassembler();
      final resultA = reassembler.add('link-1', chunksA.first);
      final resultB = reassembler.add('link-2', chunksB.first);
      expect(resultA, isNull);
      expect(resultB, isNull);
    });

    test('un enlace no puede llenar la memoria con tags distintos', () {
      final reassembler = FrameReassembler(maxPending: 4);
      final original = frame(300);
      final chunks = FrameChunker.split(original, 100);

      // El primer trozo de la trama real abre su entrada.
      expect(reassembler.add('link-1', chunks.first), isNull);

      // Ruido: 20 tags distintos con el mismo enlace.
      for (var i = 0; i < 20; i++) {
        final noise = Uint8List.fromList([
          FrameChunker.marker,
          i,
          i,
          i,
          i,
          0,
          2,
          1,
          2,
          3,
        ]);
        expect(reassembler.add('link-1', noise), isNull);
      }

      // La entrada vieja ya no está: el resto de la trama real se descarta en
      // lugar de quedar colgado para siempre.
      for (final chunk in chunks.skip(1)) {
        expect(reassembler.add('link-1', chunk), isNull);
      }
    });

    test('un trozo repetido no duplica datos', () {
      final original = frame(500);
      final chunks = FrameChunker.split(original, 100);
      final reassembler = FrameReassembler();

      expect(reassembler.add('link-1', chunks.first), isNull);
      expect(reassembler.add('link-1', chunks.first), isNull);

      Uint8List? result;
      for (final chunk in chunks.skip(1)) {
        result = reassembler.add('link-1', chunk) ?? result;
      }
      expect(result, original);
    });
  });
}
