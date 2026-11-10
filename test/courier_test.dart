import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/core/frame.dart';
import 'package:chasqui/src/core/identity.dart';
import 'package:chasqui/src/mesh/outbox.dart';
import 'package:chasqui/src/mesh/router.dart';

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

/// El mensajero resuelve el caso que la malla de saltos no puede: dos personas
/// que nunca están al alcance a la vez. Alguien recoge el mensaje, camina, y lo
/// suelta donde el destinatario sí está.
void main() {
  late NodeIdentity alice;
  late NodeIdentity bob;
  late NodeIdentity carol;
  late TestBus bus;
  late MeshRouter routerA;
  late MeshRouter routerB;
  late MeshRouter routerC;
  final inbox = <String>[];

  setUp(() async {
    alice = await NodeIdentity.generate();
    bob = await NodeIdentity.generate();
    carol = await NodeIdentity.generate();
    bus = TestBus();
    inbox.clear();

    routerA = MeshRouter(
      identity: alice,
      broadcast: (frame, {exceptLink}) => bus.deliver(frame, from: alice.id),
    );
    routerB = MeshRouter(
      identity: bob,
      broadcast: (frame, {exceptLink}) => bus.deliver(frame, from: bob.id),
    );
    routerC = MeshRouter(
      identity: carol,
      broadcast: (frame, {exceptLink}) => bus.deliver(frame, from: carol.id),
      onMessage: (from, text, hops) async => inbox.add('$text|$hops'),
    );
    bus
      ..register(routerA)
      ..register(routerB)
      ..register(routerC);
  });

  Future<void> announce(MeshRouter router, String name) async {
    await bus.deliver(router.presenceFrame(name), from: router.identity.id);
  }

  test(
    'una trama sin saltos se guarda y se suelta con saltos nuevos',
    () async {
      await announce(routerA, 'Ana');
      await announce(routerC, 'Carla');

      final frame = await routerA.buildMessageFrame(
        peer: routerA.peers[carol.id]!,
        text: 'el pozo se secó',
      );

      // Bob ni siquiera está conectado: recibe la trama ya agotada, como la
      // última persona de la cadena.
      await routerB.handlePacket(frame.refreshed(1).encode(), linkId: 'link:A');

      expect(inbox, isEmpty, reason: 'Carla todavía no está al alcance');
      expect(
        routerB.outbox.relayFrames.map((f) => f.idHex),
        contains(frame.idHex),
        reason: 'sin saltos se tiraba la trama; ahora se lleva puesta',
      );

      // Bob camina hasta donde está Carla y la suelta.
      await routerB.flushOnNewLink();

      expect(inbox.single, startsWith('el pozo se secó'));
    },
  );

  test('soltar dos veces la misma trama no repite el mensaje', () async {
    await announce(routerA, 'Ana');
    await announce(routerC, 'Carla');

    final frame = await routerA.buildMessageFrame(
      peer: routerA.peers[carol.id]!,
      text: 'una sola vez',
    );
    await routerB.handlePacket(frame.refreshed(1).encode(), linkId: 'link:A');

    await routerB.flushOnNewLink();
    await routerB.flushOnNewLink();

    expect(inbox, hasLength(1));
  });

  test('lo acarreado sobrevive a reiniciar la app', () async {
    await announce(routerA, 'Ana');
    await announce(routerC, 'Carla');

    final frame = await routerA.buildMessageFrame(
      peer: routerA.peers[carol.id]!,
      text: 'aguanta la noche',
    );
    await routerB.handlePacket(frame.refreshed(1).encode(), linkId: 'link:A');

    final saved = routerB.outbox.encode();
    final restored = Outbox()..restore(saved);

    expect(
      restored.relayFrames.map((f) => f.idHex),
      contains(frame.idHex),
      reason: 'un apagón no debe perder lo que el mensajero lleva encima',
    );
  });

  test('lo acarreado caduca a las 24 h', () {
    final outbox = Outbox();
    final frame = MeshFrame(
      type: FrameType.message,
      id: Uint8List(16),
      source: Uint8List(8),
      destination: Uint8List(8),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Uint8List(8),
    );
    outbox.enqueueRelay(frame);

    expect(outbox.relayFrames, hasLength(1));
    outbox.pruneExpired(now: DateTime.now().add(const Duration(hours: 25)));
    expect(outbox.relayFrames, isEmpty);
  });
}
