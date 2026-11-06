import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/core/bytes.dart';
import 'package:sinred/src/core/frame.dart';
import 'package:sinred/src/mesh/outbox.dart';

MeshFrame messageFrame({int timestamp = 0}) => MeshFrame(
  type: FrameType.message,
  id: randomBytes(16),
  source: randomBytes(8),
  destination: randomBytes(8),
  timestamp: timestamp,
  payload: randomBytes(16),
);

MeshFrame channelFrame({int timestamp = 0}) => MeshFrame(
  type: FrameType.channel,
  id: randomBytes(16),
  source: randomBytes(8),
  destination: MeshFrame.broadcastId,
  timestamp: timestamp,
  payload: randomBytes(24),
  ttl: 5,
);

void main() {
  group('cola del canal', () {
    test('los avisos del canal no desplazan a los mensajes privados', () {
      final outbox = Outbox(maxMessages: 3, maxChannel: 2);

      for (var i = 0; i < 3; i++) {
        outbox.enqueueOwn(messageFrame(timestamp: i));
      }
      for (var i = 0; i < 10; i++) {
        outbox.enqueueChannel(channelFrame(timestamp: i));
      }

      expect(
        outbox.ownPending.where((e) => e.frame.type == FrameType.message),
        hasLength(3),
        reason: 'los privados sin entregar no se tocan',
      );
      expect(
        outbox.ownPending.where((e) => e.frame.type == FrameType.channel),
        hasLength(2),
        reason: 'la cola del canal tiene su propio tope',
      );
    });

    test('un SOS pendiente sobrevive al reinicio en su propia cola', () {
      final original = Outbox()
        ..enqueueOwn(messageFrame())
        ..enqueueChannel(channelFrame());

      final restored = Outbox()..restore(original.encode());

      expect(restored.ownPending, hasLength(2));
      expect(
        restored.ownPending.where((e) => e.frame.type == FrameType.channel),
        hasLength(1),
      );
    });

    test('al caducar, el aviso del canal también se marca', () {
      final outbox = Outbox()
        ..enqueueOwn(messageFrame())
        ..enqueueChannel(channelFrame());

      final expired = outbox.pruneExpired(
        now: DateTime.now().add(const Duration(hours: 25)),
      );

      expect(expired, hasLength(2));
      expect(outbox.ownPending, isEmpty);
    });

    test('el aviso del canal también reintenta con espera creciente', () {
      final frame = channelFrame();
      final outbox = Outbox()..enqueueChannel(frame);
      final t0 = outbox.ownPending.single.queuedAt;

      final firstAttempt = t0.add(const Duration(seconds: 31));
      expect(
        outbox.dueForRetry(now: firstAttempt),
        hasLength(1),
        reason: 'el SOS se repite aunque no haya ACK',
      );

      outbox.markAttempt(frame.dedupKey, at: firstAttempt);
      expect(
        outbox.dueForRetry(now: t0.add(const Duration(seconds: 31 + 45))),
        isEmpty,
        reason: 'y después del intento espera el doble',
      );
    });
  });

  group('cola de salida', () {
    test('al restaurar conserva la fecha de encolado', () {
      final frame = messageFrame();
      final queuedAt = DateTime(2026, 3, 1, 10);
      final json = [
        {
          'b': base64Encode(frame.encode()),
          'q': queuedAt.millisecondsSinceEpoch,
        },
      ];

      final outbox = Outbox()
        ..restore(json, now: queuedAt.add(const Duration(hours: 2)));

      expect(outbox.ownPending, hasLength(1));
      expect(outbox.ownPending.single.key, frame.dedupKey);
      expect(outbox.ownPending.single.queuedAt, queuedAt);

      // Y caduca cuando toca, no 24 h después de cada arranque.
      final expired = outbox.pruneExpired(
        now: queuedAt.add(const Duration(hours: 25)),
      );
      expect(expired, [frame.dedupKey]);
      expect(outbox.ownPending, isEmpty);
    });

    test('al restaurar descarta lo que ya caducó', () {
      final frame = messageFrame();
      final now = DateTime(2026, 3, 2, 10);
      final json = [
        {
          'b': base64Encode(frame.encode()),
          'q': now.subtract(const Duration(hours: 30)).millisecondsSinceEpoch,
        },
      ];

      final outbox = Outbox()..restore(json, now: now);

      expect(
        outbox.ownPending,
        isEmpty,
        reason: 'un mensaje de hace 30 h no debe revivir en cada arranque',
      );
    });

    test('los reintentos esperan más después de cada intento', () {
      final frame = messageFrame();
      final outbox = Outbox()..enqueueOwn(frame);
      // El instante de encolado lo pone la cola, no el test.
      final t0 = outbox.ownPending.single.queuedAt;

      expect(
        outbox.dueForRetry(now: t0.add(const Duration(seconds: 10))),
        isEmpty,
        reason: 'todavía no toca reintentar',
      );
      expect(
        outbox.dueForRetry(now: t0.add(const Duration(seconds: 31))),
        hasLength(1),
      );

      final firstAttempt = t0.add(const Duration(seconds: 31));
      outbox.markAttempt(frame.dedupKey, at: firstAttempt);

      expect(
        outbox.dueForRetry(now: firstAttempt.add(const Duration(seconds: 45))),
        isEmpty,
        reason: 'tras un intento la espera se duplica (60 s)',
      );
      expect(
        outbox.dueForRetry(now: firstAttempt.add(const Duration(seconds: 61))),
        hasLength(1),
      );
    });

    test('los bytes de una trama corrupta no rompen la restauración', () {
      final outbox = Outbox()
        ..restore([
          {
            'b': base64Encode(Uint8List.fromList([1, 2, 3])),
            'q': 0,
          },
          {'b': 'no-es-base64!!!', 'q': 0},
        ]);

      expect(outbox.ownPending, isEmpty);
    });

    test('mete como mucho maxMessages y tira lo más viejo', () {
      final outbox = Outbox(maxMessages: 3);
      final frames = List.generate(5, (_) => messageFrame());
      for (final frame in frames) {
        outbox.enqueueOwn(frame);
      }

      expect(outbox.ownPending, hasLength(3));
      expect(
        outbox.ownPending.map((e) => e.key),
        containsAll(frames.skip(2).map((f) => f.dedupKey)),
      );
    });
  });
}
