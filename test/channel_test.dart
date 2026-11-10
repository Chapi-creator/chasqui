import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/core/bytes.dart';
import 'package:chasqui/src/core/channel.dart';
import 'package:chasqui/src/core/frame.dart';
import 'package:chasqui/src/core/geo.dart';
import 'package:chasqui/src/core/identity.dart';
import 'package:chasqui/src/core/models.dart';
import 'package:chasqui/src/data/state_store.dart';
import 'package:chasqui/src/mesh/mesh_node.dart';
import 'package:chasqui/src/mesh/router.dart';

import 'support/fake_transport.dart';

void main() {
  group('contenido del canal', () {
    test('ida y vuelta conserva texto, nombre, batería y posición', () {
      final message = ChannelMessage(
        name: 'Ana',
        text: 'Agua en la escuela',
        kind: ChannelKind.sos,
        battery: 42,
        point: GeoPoint(
          lat: 4.60971,
          lon: -74.08175,
          accuracy: 12,
          at: DateTime.now(),
        ),
      );

      final decoded = ChannelMessage.decode(message.encode())!;
      expect(decoded.text, 'Agua en la escuela');
      expect(decoded.name, 'Ana');
      expect(decoded.kind, ChannelKind.sos);
      expect(decoded.battery, 42);
      expect(decoded.point!.lat, closeTo(4.60971, 1e-6));
      expect(decoded.point!.lon, closeTo(-74.08175, 1e-6));
    });

    test('un mensaje sin texto o basura se descarta', () {
      expect(ChannelMessage.decode(utf8.encode('{"t":"   "}')), isNull);
      expect(ChannelMessage.decode(<int>[1, 2, 3, 4]), isNull);
      expect(ChannelMessage.decode(utf8.encode('no es json')), isNull);
    });

    test('el texto largo se recorta a lo que cabe en la malla', () {
      final decoded = ChannelMessage.decode(
        ChannelMessage(name: 'Ana', text: 'x' * 5000).encode(),
      )!;
      expect(
        utf8.encode(decoded.text).length,
        lessThanOrEqualTo(ChannelMessage.maxTextBytes),
      );
    });

    test('un tipo desconocido se lee como mensaje normal', () {
      final decoded = ChannelMessage.decode(
        utf8.encode('{"t":"hola","k":"cosa-rara"}'),
      )!;
      expect(decoded.kind, ChannelKind.message);
    });
  });

  group('cifrado del canal', () {
    test('lo que se cifra se descifra con el mismo AAD', () async {
      final sealed = await ChannelCrypto.seal(
        plaintext: utf8.encode('aviso'),
        aad: <int>[7, 7, 7],
      );
      final clear = await ChannelCrypto.open(
        sealed: sealed,
        aad: <int>[7, 7, 7],
      );
      expect(utf8.decode(clear), 'aviso');
    });

    test('una trama manipulada no descifra', () async {
      final sealed = await ChannelCrypto.seal(
        plaintext: utf8.encode('aviso'),
        aad: <int>[7, 7, 7],
      );
      await expectLater(
        ChannelCrypto.open(sealed: sealed, aad: <int>[8, 8, 8]),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final tampered = Uint8List.fromList(sealed);
      tampered[0] ^= 0xFF;
      await expectLater(
        ChannelCrypto.open(sealed: tampered, aad: <int>[7, 7, 7]),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('trama del canal', () {
    late NodeIdentity identity;
    late MeshRouter router;
    late List<MeshFrame> out;

    setUp(() async {
      identity = await NodeIdentity.generate();
      out = <MeshFrame>[];
      router = MeshRouter(
        identity: identity,
        broadcast: (frame, {String? exceptLink}) async {
          out.add(frame);
        },
      );
    });

    test('va a difusión, con más saltos y sin destinatario', () async {
      final frame = await router.buildChannelFrame(
        ChannelMessage(name: 'Ana', text: 'hola a todos'),
      );
      expect(frame.type, FrameType.channel);
      expect(frame.isBroadcast, isTrue);
      expect(frame.ttl, MeshRouter.channelTtl);
      expect(
        frame.destinationHex,
        MeshFrame.broadcastId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      );
    });

    test('se entrega aunque el emisor sea desconocido y se reenvía', () async {
      final sender = MeshRouter(
        identity: identity,
        broadcast: (frame, {String? exceptLink}) async {},
      );
      final frame = await sender.buildChannelFrame(
        ChannelMessage(name: 'Desconocido', text: 'necesito ayuda'),
      );

      final receiverIdentity = await NodeIdentity.generate();
      final received = <ChannelMessage>[];
      final relays = <MeshFrame>[];
      final receiver = MeshRouter(
        identity: receiverIdentity,
        broadcast: (f, {String? exceptLink}) async => relays.add(f),
        onChannel: (sourceId, message, hops) => received.add(message),
      );

      await receiver.handlePacket(frame.encode(), linkId: 'link-1');

      expect(received, hasLength(1));
      expect(received.single.text, 'necesito ayuda');
      expect(receiver.relayed, 1, reason: 'un aviso debe seguir de largo');
      expect(relays.single.ttl, MeshRouter.channelTtl - 1);
      expect(relays.single.hops, 1);
    });

    test('una trama de canal corrupta no rompe la malla', () async {
      final frame = MeshFrame(
        type: FrameType.channel,
        id: randomBytes(16),
        source: Uint8List(8),
        destination: MeshFrame.broadcastId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: randomBytes(40),
        ttl: 3,
      );
      final relays = <MeshFrame>[];
      final receiver = MeshRouter(
        identity: await NodeIdentity.generate(),
        broadcast: (f, {String? exceptLink}) async => relays.add(f),
        onChannel: (_, _, _) => fail('no debería entregar basura'),
      );
      await receiver.handlePacket(frame.encode());
      // Ya no se repite: antes, una trama que nadie podía descifrar se
      // reenviaba con TTL 5 y convertía el ruido en una inundación.
      expect(receiver.relayed, 0);
      expect(relays, isEmpty);
    });
  });

  group('canal en el nodo', () {
    late Directory directory;
    late FakeTransport transport;
    late MeshNode node;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('chasqui_channel_test');
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

    test(
      'un aviso propio sale por el enlace y queda en el historial',
      () async {
        transport.connect('link-1');

        await node.sendChannelMessage('Hay agua en la escuela');
        await pumpEventQueue();

        final message = node.channelMessages.single;
        expect(message.text, 'Hay agua en la escuela');
        expect(message.kind, MessageKind.text);
        expect(message.status, MessageStatus.sent);
        expect(message.senderName, isNotEmpty);

        final frame = MeshFrame.decode(transport.sent.last);
        expect(frame.type, FrameType.channel);
        expect(frame.isBroadcast, isTrue);
        final clear = await ChannelCrypto.open(
          sealed: frame.payload,
          aad: frame.authenticatedHeader(),
        );
        expect(ChannelMessage.decode(clear)!.text, 'Hay agua en la escuela');
      },
    );

    test('sin enlaces un aviso normal no se guarda', () async {
      await node.sendChannelMessage('aviso al aire');

      expect(node.channelMessages.single.status, MessageStatus.failed);
      expect(node.pendingCount, 0);
    });

    test('el SOS se guarda en cola y lleva la posición', () async {
      node.updateMyLocation(
        GeoPoint(lat: 4.60971, lon: -74.08175, accuracy: 9, at: DateTime.now()),
      );

      await node.sendSos();
      await pumpEventQueue();

      final message = node.channelMessages.single;
      expect(message.kind, MessageKind.sos);
      expect(message.status, MessageStatus.queued);
      expect(node.pendingCount, 1, reason: 'un SOS se reintenta solo');

      final clear = await ChannelCrypto.open(
        sealed: MeshFrame.decode(transport.sent.last).payload,
        aad: MeshFrame.decode(transport.sent.last).authenticatedHeader(),
      );
      final sent = ChannelMessage.decode(clear)!;
      expect(sent.kind, ChannelKind.sos);
      expect(sent.point!.lat, closeTo(4.60971, 1e-6));
      expect(sent.battery, isNotNull);
    });

    test('el SOS adjunta una posición recién pedida al GPS', () async {
      // Compartir ubicación está apagado: sin la posición explícita el SOS
      // salía sin coordenadas justo cuando más importan.
      await node.sendSos(
        point: GeoPoint(
          lat: 6.2442,
          lon: -75.5812,
          accuracy: 18,
          at: DateTime.now(),
        ),
      );

      final frame = MeshFrame.decode(transport.sent.last);
      final clear = await ChannelCrypto.open(
        sealed: frame.payload,
        aad: frame.authenticatedHeader(),
      );
      final sent = ChannelMessage.decode(clear)!;
      expect(sent.kind, ChannelKind.sos);
      expect(sent.point!.lat, closeTo(6.2442, 1e-6));
    });

    test('un estado rápido avisa y se ve como estado', () async {
      final alerts = <ChannelAlert>[];
      final subscription = node.channelAlerts.listen(alerts.add);
      final ana = await NodeIdentity.generate();
      final sender = MeshRouter(
        identity: ana,
        broadcast: (frame, {String? exceptLink}) async {},
      );
      final frame = await sender.buildChannelFrame(
        ChannelMessage(
          name: 'Ana',
          text: QuickStatus.help.label,
          kind: ChannelKind.status,
          battery: 20,
        ),
      );

      transport.incoming('link-1', frame.encode());
      await pumpEventQueue();

      expect(node.channelMessages.single.kind, MessageKind.status);
      expect(node.channelMessages.single.senderName, 'Ana');
      expect(alerts.single.kind, ChannelKind.status);
      expect(alerts.single.name, 'Ana');
      await subscription.cancel();
    });

    test('el modo repetidor se guarda y cambia el plan de radio', () async {
      await node.setRelayMode(true);
      expect(node.relayMode, isTrue);
      expect(node.scanPlan.window, const Duration(seconds: 8));

      await node.stop();
      final saved = await StateStore(directory: directory).load();
      expect(saved!.relayMode, isTrue);
    });

    test('el tipo de mensaje del canal sobrevive al JSON', () {
      final message = ChatMessage(
        id: '1',
        peerId: MeshNode.channelId,
        outgoing: false,
        text: 'Necesito ayuda',
        timestamp: DateTime.now(),
        kind: MessageKind.sos,
        senderName: 'Ana',
      );

      final restored = ChatMessage.fromJson(message.toJson());
      expect(restored.kind, MessageKind.sos);
      expect(restored.senderName, 'Ana');
      expect(restored.peerId, MeshNode.channelId);
    });
  });
}
