import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/core/frame.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/core/models.dart';
import 'package:sinred/src/mesh/router.dart';

/// Radio de mentira: entrega la trama a todos los routers menos al emisor.
class TestBus {
  final Map<String, MeshRouter> routers = <String, MeshRouter>{};

  void register(MeshRouter router) => routers[router.identity.id] = router;

  Future<void> deliver(MeshFrame frame, {required String from}) async {
    for (final entry in routers.entries) {
      if (entry.key == from) continue;
      await entry.value.handlePacket(frame.encode(), linkId: 'link:$from');
    }
  }
}

void main() {
  late NodeIdentity alice;
  late NodeIdentity bob;
  late NodeIdentity carol;
  late TestBus bus;
  late MeshRouter routerA;
  late MeshRouter routerB;
  late MeshRouter routerC;
  final inbox = <String>[];
  final acks = <String>[];

  setUp(() async {
    alice = await NodeIdentity.generate();
    bob = await NodeIdentity.generate();
    carol = await NodeIdentity.generate();
    bus = TestBus();
    inbox.clear();
    acks.clear();

    routerA = MeshRouter(
      identity: alice,
      broadcast: (frame, {exceptLink}) => bus.deliver(frame, from: alice.id),
      onAck: (key, peer) => acks.add(key),
    );
    routerB = MeshRouter(
      identity: bob,
      broadcast: (frame, {exceptLink}) => bus.deliver(frame, from: bob.id),
      onMessage: (from, text, hops) async => inbox.add('$text|${from.name}|$hops'),
      onAck: (key, peer) => acks.add(key),
    );
    routerC = MeshRouter(
      identity: carol,
      broadcast: (frame, {exceptLink}) => bus.deliver(frame, from: carol.id),
      onMessage: (from, text, hops) async => inbox.add('C:no-deberia'),
    );
    bus
      ..register(routerA)
      ..register(routerB)
      ..register(routerC);
  });

  Future<void> announce(MeshRouter router, String name) async {
    final frame = router.presenceFrame(name);
    await bus.deliver(frame, from: router.identity.id);
  }

  test('dos nodos se descubren y se entrega el mensaje con confirmación',
      () async {
    await announce(routerA, 'Ana');
    await announce(routerB, 'Beto');

    expect(routerA.peers[bob.id]?.name, 'Beto');
    expect(routerB.peers[alice.id]?.name, 'Ana');

    final frame = await routerA.buildMessageFrame(
      peer: routerA.peers[bob.id]!,
      text: 'hola desde el sótano',
    );
    routerA.outbox.enqueueOwn(frame);
    await bus.deliver(frame, from: alice.id);

    expect(inbox.single, 'hola desde el sótano|Ana|0');
    expect(routerA.outbox.ownPending, isEmpty,
        reason: 'el ACK debe sacar el mensaje de la cola');
    expect(acks, contains(frame.dedupKey));
  });

  test('un tercer nodo repite sin poder leer', () async {
    await announce(routerA, 'Ana');
    await announce(routerB, 'Beto');
    await announce(routerC, 'Carla');

    final frame = await routerA.buildMessageFrame(
      peer: routerA.peers[bob.id]!,
      text: 'mensaje cifrado',
    );
    routerA.outbox.enqueueOwn(frame);

    // La trama pasa por C antes de llegar a B: simulamos el salto.
    await routerC.handlePacket(frame.encode(), linkId: 'link:A');
    expect(routerC.peers.keys, contains(alice.id));

    expect(inbox, isNot(contains('C:no-deberia')),
        reason: 'el repetidor no descifra ni entrega ajeno');

    final decoded = MeshFrame.decode(frame.encode());
    await routerB.handlePacket(decoded.forwarded().encode(), linkId: 'link:C');

    expect(inbox.single, startsWith('mensaje cifrado'));
  });

  test('el mismo paquete dos veces no duplica el mensaje', () async {
    await announce(routerA, 'Ana');
    await announce(routerB, 'Beto');

    final frame = await routerA.buildMessageFrame(
      peer: routerA.peers[bob.id]!,
      text: 'una sola vez',
    );
    await routerB.handlePacket(frame.encode(), linkId: 'link:A');
    await routerB.handlePacket(frame.encode(), linkId: 'link:A');

    expect(inbox, hasLength(1));
  });

  test('el TTL evita inundaciones infinitas', () async {
    await announce(routerA, 'Ana');
    await announce(routerB, 'Beto');

    final frame = MeshFrame(
      type: FrameType.message,
      id: (await routerA.buildMessageFrame(
        peer: routerA.peers[bob.id]!,
        text: 'x',
      ))
          .id,
      source: alice.nodeId,
      destination: bob.nodeId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: (await routerA.buildMessageFrame(
        peer: routerA.peers[bob.id]!,
        text: 'x',
      ))
          .payload,
      ttl: 1,
    );

    expect(frame.forwarded().ttl, 0);
    expect(MeshFrame.decode(frame.encode()).ttl, 1);
  });

  test('si el mensaje llega antes que la presencia, el reintento lo entrega',
      () async {
    // El emisor pasa por un repetidor, así que B recibe su mensaje antes de
    // haber visto nunca su anuncio de presencia.
    final stranger = await NodeIdentity.generate();
    final strangerRouter = MeshRouter(
      identity: stranger,
      broadcast: (frame, {exceptLink}) async {},
    );
    final frame = await strangerRouter.buildMessageFrame(
      peer: PeerRecord(
        id: bob.id,
        name: 'Beto',
        publicKey: bob.publicKeyBytes,
        lastSeen: DateTime.now(),
      ),
      text: 'llego antes que mi dueño',
    );

    await routerB.handlePacket(frame.encode(), linkId: 'link:C');
    expect(inbox, isEmpty, reason: 'todavía no conoce al emisor');

    // La presencia llega después...
    await announce(strangerRouter, 'Desconocido');
    // ...y el emisor reintenta la misma trama (misma id, no una nueva).
    await routerB.handlePacket(frame.encode(), linkId: 'link:C');

    expect(inbox.single, startsWith('llego antes que mi dueño'),
        reason: 'marcar como vista una trama no entregable la perdía para siempre');
  });

  test('un mensaje de un nodo desconocido no se entrega', () async {
    final stranger = await NodeIdentity.generate();
    final strangerRouter = MeshRouter(
      identity: stranger,
      broadcast: (frame, {exceptLink}) async {},
    );
    bus.register(strangerRouter);

    await announce(routerB, 'Beto');
    final frame = await strangerRouter.buildMessageFrame(
      peer: PeerRecord(
        id: bob.id,
        name: 'Beto',
        publicKey: bob.publicKeyBytes,
        lastSeen: DateTime.now(),
      ),
      text: 'intruso',
    );

    await routerB.handlePacket(frame.encode(), linkId: 'link:X');
    expect(inbox, isEmpty);
  });
}
