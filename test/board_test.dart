import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/core/board.dart';
import 'package:sinred/src/core/channel.dart';
import 'package:sinred/src/core/frame.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/core/models.dart';
import 'package:sinred/src/data/state_store.dart';
import 'package:sinred/src/mesh/mesh_node.dart';
import 'package:sinred/src/mesh/router.dart';

import 'support/fake_transport.dart';

ChatMessage _post({
  required BoardCategory category,
  required DateTime at,
  DateTime? expiresAt,
  String text = 'Necesito agua',
}) => ChatMessage(
  id: 'p${at.microsecondsSinceEpoch}',
  peerId: MeshNode.channelId,
  outgoing: false,
  text: text,
  timestamp: at,
  kind: MessageKind.board,
  board: category,
  expiresAt: expiresAt ?? at.add(category.validFor),
  senderName: 'Ana',
);

void main() {
  group('categorías del tablero', () {
    test('cada categoría tiene su plazo y su código corto', () {
      expect(BoardCategory.danger.validFor, const Duration(hours: 2));
      expect(BoardCategory.need.validFor, const Duration(hours: 12));
      expect(BoardCategory.missing.validFor, const Duration(hours: 48));

      for (final category in BoardCategory.values) {
        expect(BoardCategory.fromCode(category.code), category);
      }
      expect(BoardCategory.fromCode('inventada'), isNull);
      expect(BoardCategory.fromCode(null), isNull);
    });

    test('los avisos caducados dejan de mostrarse', () {
      final now = DateTime(2026, 11, 6, 12);
      final vigente = _post(
        category: BoardCategory.need,
        at: now,
        text: 'agua',
      );
      // Un peligro de hace 3 h ya caducó (dura 2 h).
      final viejo = _post(
        category: BoardCategory.danger,
        at: now.subtract(const Duration(hours: 3)),
        text: 'derrumbe en la esquina',
      );

      final posts = activeBoardPosts([viejo, vigente], now: now);
      expect(posts.single.text, 'agua');
      expect(
        activeBoardPosts([viejo], now: now),
        isEmpty,
        reason: 'dar por bueno un peligro de hace 3 h es peor que no tenerlo',
      );
    });

    test('se ordenan de más nuevo a más viejo y se filtran por categoría', () {
      final now = DateTime(2026, 11, 6, 12);
      final older = _post(
        category: BoardCategory.need,
        at: now.subtract(const Duration(minutes: 30)),
        text: 'agua',
      );
      final newer = _post(
        category: BoardCategory.need,
        at: now.subtract(const Duration(minutes: 5)),
        text: 'medicinas',
      );
      final other = _post(
        category: BoardCategory.offer,
        at: now,
        text: 'tengo un camión',
      );

      final needs = activeBoardPosts(
        [older, other, newer],
        category: BoardCategory.need,
        now: now,
      );
      expect(needs.map((p) => p.text), ['medicinas', 'agua']);
      expect(
        activeBoardPosts([older, other, newer], now: now).first.text,
        'tengo un camión',
      );
    });

    test('el plazo se cuenta en palabras', () {
      final now = DateTime(2026, 11, 6, 12);
      expect(
        formatBoardRemaining(now.add(const Duration(minutes: 20)), now: now),
        'caduca en 20 min',
      );
      expect(
        formatBoardRemaining(now.add(const Duration(hours: 5)), now: now),
        'caduca en 5 h',
      );
      expect(
        formatBoardRemaining(
          now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        'caducado',
      );
    });
  });

  group('el aviso viaja en el canal', () {
    test('ida y vuelta conserva la categoría y la caducidad', () {
      final expiresAt = DateTime.now().add(const Duration(hours: 3));
      final message = ChannelMessage(
        name: 'Ana',
        text: 'Busco a mi hermano Julián, visto cerca de la plaza',
        board: BoardCategory.missing,
        expiresAt: expiresAt,
      );

      final decoded = ChannelMessage.decode(message.encode())!;
      expect(decoded.board, BoardCategory.missing);
      expect(
        decoded.expiresAt!.difference(expiresAt).inSeconds.abs(),
        lessThanOrEqualTo(1),
      );
      expect(decoded.text, startsWith('Busco a mi hermano'));
    });

    test('un aviso de una app anterior se lee como mensaje normal', () {
      // Sin "cat" no hay tablero: la app vieja sigue mostrando el texto.
      final decoded = ChannelMessage.decode(
        utf8.encode('{"v":1,"n":"Ana","t":"hay agua","k":"msg"}'),
      )!;
      expect(decoded.board, isNull);
      expect(decoded.expiresAt, isNull);
    });

    test('nadie puede dejar un aviso vigente para siempre', () {
      final now = DateTime.now();
      final decoded = ChannelMessage.decode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'n': 'Ana',
            't': 'derrumbe',
            'k': 'msg',
            'cat': 'danger',
            'exp': now.add(const Duration(days: 30)).millisecondsSinceEpoch,
          }),
        ),
      )!;
      expect(decoded.board, BoardCategory.danger);
      // El tope es el doble del plazo de la categoría (2 h → 4 h).
      expect(
        decoded.expiresAt!.isAfter(
          now.add(const Duration(hours: 4, minutes: 1)),
        ),
        isFalse,
      );
    });

    test('la categoría y la caducidad sobreviven al historial en disco', () {
      final original = _post(
        category: BoardCategory.danger,
        at: DateTime.now(),
        text: 'no crucen el puente',
      );

      final restored = ChatMessage.fromJson(original.toJson());
      expect(restored.kind, MessageKind.board);
      expect(restored.board, BoardCategory.danger);
      expect(
        restored.expiresAt!.millisecondsSinceEpoch,
        original.expiresAt!.millisecondsSinceEpoch,
      );
    });
  });

  group('tablero en el nodo', () {
    late Directory directory;
    late FakeTransport transport;
    late MeshNode node;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sinred_board_test');
      transport = FakeTransport();
      node = MeshNode(
        identity: await NodeIdentity.generate(),
        store: StateStore(directory: directory),
        transport: transport,
        monitorBattery: false,
      );
      await node.start();
    });

    tearDown(() async {
      await transport.close();
      node.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('publicar sin enlaces lo deja en cola (no se pierde)', () async {
      await node.sendBoardPost(BoardCategory.need, 'Agua para dos familias');

      final message = node.channelMessages.single;
      expect(message.kind, MessageKind.board);
      expect(message.board, BoardCategory.need);
      expect(message.expiresAt, isNotNull);
      expect(message.status, MessageStatus.queued);
      expect(node.pendingCount, 1, reason: 'sale cuando aparezca alguien');
      expect(node.boardPosts(BoardCategory.need), hasLength(1));
    });

    test('el aviso sale con su categoría dentro de la trama', () async {
      transport.connect('link-1');

      await node.sendBoardPost(BoardCategory.danger, 'Derrumbe en la 45');
      await pumpEventQueue();

      final frame = MeshFrame.decode(transport.sent.last);
      expect(frame.type, FrameType.channel);
      final clear = await ChannelCrypto.open(
        sealed: frame.payload,
        aad: frame.authenticatedHeader(),
      );
      final sent = ChannelMessage.decode(clear)!;
      expect(sent.board, BoardCategory.danger);
      expect(sent.text, 'Derrumbe en la 45');
      expect(
        sent.expiresAt!.difference(DateTime.now()).inHours,
        lessThanOrEqualTo(2),
      );
    });

    test('un aviso recibido entra en el tablero con su categoría', () async {
      final sender = MeshRouter(
        identity: await NodeIdentity.generate(),
        broadcast: (frame, {String? exceptLink}) async {},
      );
      final frame = await sender.buildChannelFrame(
        ChannelMessage(
          name: 'Ana',
          text: 'Ofrezco cargar teléfonos en la panadería',
          board: BoardCategory.offer,
        ),
      );

      transport.incoming('link-1', frame.encode());
      await pumpEventQueue();

      final received = node.channelMessages.single;
      expect(received.kind, MessageKind.board);
      expect(received.board, BoardCategory.offer);
      expect(received.senderName, 'Ana');

      final posts = node.boardPosts(BoardCategory.offer);
      expect(posts.single.text, startsWith('Ofrezco cargar'));
      expect(
        node.boardPosts(BoardCategory.need),
        isEmpty,
        reason: 'no se mezclan categorías',
      );
    });

    test('el aviso del tablero sobrevive al reinicio del nodo', () async {
      transport.connect('link-1');
      await node.sendBoardPost(BoardCategory.need, 'Falta insulina');
      await pumpEventQueue();
      await node.stop();

      final saved = await StateStore(directory: directory).load();
      final restored = saved!.messages.firstWhere(
        (m) => m.kind == MessageKind.board,
      );
      expect(restored.board, BoardCategory.need);
      expect(restored.text, 'Falta insulina');
      expect(restored.expiresAt, isNotNull);
    });
  });
}
