import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/core/frame.dart';
import 'package:sinred/src/core/geo.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/core/models.dart';
import 'package:sinred/src/data/state_store.dart';
import 'package:sinred/src/mesh/mesh_node.dart';
import 'package:sinred/src/mesh/router.dart';

import 'support/fake_transport.dart';

void main() {
  late Directory directory;
  late FakeTransport transport;
  late MeshNode node;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sinred_node_test');
    final identity = await NodeIdentity.generate();
    transport = FakeTransport();
    node = MeshNode(
      identity: identity,
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

  Future<void> announce(String linkId, {String name = 'Ana'}) async {
    final peerIdentity = await NodeIdentity.generate();
    transport.incoming(
      linkId,
      MeshFrame.presence(
        source: peerIdentity.nodeId,
        publicKey: peerIdentity.publicKey,
        name: name,
      ).encode(),
    );
    await pumpEventQueue();
  }

  test('al parar la radio ningún nodo sigue marcado como enlace directo',
      () async {
    transport.connect('link-1');
    await announce('link-1');
    await pumpEventQueue();

    final peer = node.peers.single;
    expect(peer.name, 'Ana');
    expect(peer.directLink, isTrue);
    expect(peer.rssi, -55, reason: 'la señal del enlace debe llegar al nodo');

    await node.stop();

    expect(node.connectedLinks, 0);
    expect(node.peers.single.directLink, isFalse,
        reason: 'sin enlaces no se puede mostrar "Enlace directo"');
    expect(node.peers.single.rssi, isNull);
  });

  test('al parar se guarda el estado pendiente', () async {
    transport.connect('link-1');
    await announce('link-1');
    await pumpEventQueue();

    // Al parar se espera el guardado, así que no hace falta esperar nada más.
    await node.stop();

    final file = File(
      '${directory.path}${Platform.pathSeparator}sinred_state.json',
    );
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('Ana'));
  });

  test('un mensaje gigante se recorta a lo que cabe en la malla', () async {
    transport.connect('link-1');
    await announce('link-1');
    await pumpEventQueue();

    await node.sendMessage(node.peers.single.id, 'a' * 5000);
    await pumpEventQueue();

    final sent = node.messages.single;
    expect(sent.text, isNotEmpty);
    expect(
      utf8.encode(sent.text).length,
      lessThanOrEqualTo(MeshNode.maxMessageBytes),
      reason: 'la fragmentación BLE solo admite 255 trozos',
    );
  });

  test('el nombre local se recorta a lo que se anuncia', () {
    node.setDisplayName('📡' * 40);

    expect(
      utf8.encode(node.displayName).length,
      lessThanOrEqualTo(MeshFrame.maxNameBytes),
      reason: 'si no, tú verías un nombre y los demás otro',
    );
  });

  test('recibir coordenadas deja el mensaje y el asistente', () async {
    node.setShowProximity(true);
    node.updateMyLocation(GeoPoint(
      lat: 0,
      lon: 0,
      accuracy: 5,
      at: DateTime.now(),
    ));
    final ana = await NodeIdentity.generate();
    transport.incoming(
      'link-1',
      MeshFrame.presence(
        source: ana.nodeId,
        publicKey: ana.publicKey,
        name: 'Ana',
      ).encode(),
    );
    await pumpEventQueue();

    final sender = MeshRouter(
      identity: ana,
      broadcast: (frame, {String? exceptLink}) async {},
    );
    final frame = await sender.buildLocationFrame(
      peer: PeerRecord(
        id: node.identity.id,
        name: 'Yo',
        publicKey: node.identity.publicKeyBytes,
        lastSeen: DateTime.now(),
      ),
      point: GeoPoint(
        lat: 0,
        lon: 0.001,
        accuracy: 8,
        at: DateTime.now(),
      ),
    );
    transport.incoming('link-1', frame.encode());
    await pumpEventQueue();

    final peer = node.peers.single;
    expect(peer.location, isNotNull);
    expect(peer.location!.lon, closeTo(0.001, 1e-6));

    final messages = node.messagesFor(peer.id);
    expect(
      messages.where((m) => m.kind == MessageKind.location),
      hasLength(1),
    );
    final assistant = messages.singleWhere(
      (m) => m.kind == MessageKind.assistant,
    );
    expect(assistant.text, contains('≈110 m al E'));
  });

  test('con la cercanía apagada no se genera el asistente', () async {
    final ana = await NodeIdentity.generate();
    transport.incoming(
      'link-1',
      MeshFrame.presence(
        source: ana.nodeId,
        publicKey: ana.publicKey,
        name: 'Ana',
      ).encode(),
    );
    await pumpEventQueue();

    final sender = MeshRouter(
      identity: ana,
      broadcast: (frame, {String? exceptLink}) async {},
    );
    final frame = await sender.buildLocationFrame(
      peer: PeerRecord(
        id: node.identity.id,
        name: 'Yo',
        publicKey: node.identity.publicKeyBytes,
        lastSeen: DateTime.now(),
      ),
      point: GeoPoint(lat: 0, lon: 0, accuracy: 8, at: DateTime.now()),
    );
    transport.incoming('link-1', frame.encode());
    await pumpEventQueue();

    final messages = node.messagesFor(node.peers.single.id);
    expect(messages.where((m) => m.kind == MessageKind.location), hasLength(1));
    expect(messages.where((m) => m.kind == MessageKind.assistant), isEmpty);
    expect(node.proximityLabel(node.peers.single), isNull);
  });

  test('enviar mi ubicación usa el enlace y queda en el historial', () async {
    transport.connect('link-1');
    await announce('link-1');
    await pumpEventQueue();

    final peer = node.peers.single;
    node.updateMyLocation(GeoPoint(
      lat: 4.60971,
      lon: -74.08175,
      accuracy: 9,
      at: DateTime.now(),
    ));
    final sent = await node.sendMyLocation(peer.id);
    await pumpEventQueue();

    expect(sent, isTrue);
    final message = node.messagesFor(peer.id).single;
    expect(message.kind, MessageKind.location);
    expect(message.status, MessageStatus.sent);
    expect(message.location!.lat, closeTo(4.60971, 1e-6));
    expect(transport.sent, isNotEmpty);
  });

  test('sin enlace la ubicación no se guarda en cola', () async {
    await announce('link-1');
    await pumpEventQueue();

    final peer = node.peers.single;
    node.updateMyLocation(GeoPoint(
      lat: 1,
      lon: 2,
      accuracy: 9,
      at: DateTime.now(),
    ));
    final sent = await node.sendMyLocation(peer.id);

    expect(sent, isFalse);
    expect(node.messagesFor(peer.id).single.status, MessageStatus.failed);
    expect(node.pendingCount, 0, reason: 'una ubicación vieja no sirve mañana');
  });
}
