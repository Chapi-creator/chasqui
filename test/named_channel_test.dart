import 'dart:io';

import 'package:chasqui/src/core/frame.dart';
import 'package:chasqui/src/core/identity.dart';
import 'package:chasqui/src/core/named_channel.dart';
import 'package:chasqui/src/core/channel.dart';
import 'package:chasqui/src/data/state_store.dart';
import 'package:chasqui/src/mesh/mesh_node.dart';
import 'package:chasqui/src/mesh/router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  group('nombre del canal', () {
    test('mayúsculas y espacios de más no crean canales distintos', () async {
      final a = await NamedChannel.create(name: 'Refugio Norte');
      final b = await NamedChannel.create(name: '  refugio   NORTE ');
      expect(b.id, a.id);
      expect(b.name, 'refugio NORTE');
    });

    test('la clave cambia el canal: sin ella no se mezclan', () async {
      final open = await NamedChannel.create(name: 'Cuadrilla 3');
      final closed = await NamedChannel.create(
        name: 'Cuadrilla 3',
        passphrase: 'linterna',
      );
      expect(closed.id, isNot(open.id));
      expect(closed.isPrivate, isTrue);
      expect(open.isPrivate, isFalse);
    });

    test('la misma clave da la misma llave en dos teléfonos', () async {
      final a = await NamedChannel.create(
        name: 'Edificio B',
        passphrase: '4321',
      );
      final b = await NamedChannel.create(
        name: 'edificio b',
        passphrase: '4321',
      );
      expect(b.id, a.id);
      final keyA = await a.key();
      final keyB = await b.key();
      expect(await keyA.extractBytes(), await keyB.extractBytes());
    });

    test('un nombre vacío o larguísimo no es válido', () {
      expect(NamedChannel.isValidName(''), isFalse);
      expect(NamedChannel.isValidName(' a '), isFalse);
      expect(NamedChannel.isValidName('a' * 33), isFalse);
      expect(NamedChannel.isValidName('Refugio Norte'), isTrue);
    });
  });

  group('trama del canal con nombre', () {
    test('se entrega al miembro y se reenvía; el ajeno no la repite', () async {
      final sender = await NodeIdentity.generate();
      final channel = await NamedChannel.create(
        name: 'Refugio Norte',
        passphrase: 'agua',
      );
      final key = await channel.key();
      final senderRouter = MeshRouter(
        identity: sender,
        broadcast: (frame, {String? exceptLink}) async {},
      );
      final frame = await senderRouter.buildNamedChannelFrame(
        channel: channel,
        key: key,
        message: ChannelMessage(name: 'Ana', text: 'Hay mantas'),
      );

      final memberIdentity = await NodeIdentity.generate();
      final received = <ChannelMessage>[];
      final relays = <MeshFrame>[];
      final member = MeshRouter(
        identity: memberIdentity,
        broadcast: (f, {String? exceptLink}) async => relays.add(f),
        resolveNamedChannelKey: (id) async =>
            id == channel.id ? await channel.key() : null,
        onNamedChannel: (channelId, sourceId, message, hops) {
          expect(channelId, channel.id);
          received.add(message);
        },
      );
      await member.handlePacket(frame.encode(), linkId: 'link-1');
      expect(received.single.text, 'Hay mantas');
      expect(received.single.name, 'Ana');
      expect(member.relayed, 1);
      expect(relays.single.ttl, MeshRouter.channelTtl - 1);

      // Alguien que no está en el canal ni siquiera puede descifrarlo: no lo
      // reenvía, para no inundar la malla con algo que nadie alrededor lee.
      final strangerIdentity = await NodeIdentity.generate();
      final strangerRelays = <MeshFrame>[];
      final stranger = MeshRouter(
        identity: strangerIdentity,
        broadcast: (f, {String? exceptLink}) async => strangerRelays.add(f),
        resolveNamedChannelKey: (id) async => null,
        onNamedChannel: (_, _, _, _) => fail('no debería poder leerlo'),
      );
      await stranger.handlePacket(frame.encode(), linkId: 'link-2');
      expect(stranger.relayed, 0);
      expect(strangerRelays, isEmpty);
    });

    test('con otra clave no descifra aunque el nombre coincida', () async {
      final channel = await NamedChannel.create(
        name: 'Cuadrilla 3',
        passphrase: 'uno',
      );
      final other = await NamedChannel.create(
        name: 'Cuadrilla 3',
        passphrase: 'dos',
      );
      final router = MeshRouter(
        identity: await NodeIdentity.generate(),
        broadcast: (frame, {String? exceptLink}) async {},
      );
      final frame = await router.buildNamedChannelFrame(
        channel: channel,
        key: await channel.key(),
        message: ChannelMessage(name: 'Ana', text: 'Bajamos por el río'),
      );
      final received = <ChannelMessage>[];
      final otherRouter = MeshRouter(
        identity: await NodeIdentity.generate(),
        broadcast: (f, {String? exceptLink}) async {},
        resolveNamedChannelKey: (id) async =>
            id == other.id ? await other.key() : null,
        onNamedChannel: (_, _, message, _) => received.add(message),
      );
      await otherRouter.handlePacket(frame.encode());
      expect(received, isEmpty);
    });
  });

  group('canales en el nodo', () {
    late Directory directory;
    late FakeTransport transport;
    late MeshNode node;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('chasqui_named_test');
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

    test('entrar dos veces no duplica y quedar guardado sobrevive', () async {
      final first = await node.joinChannel(name: 'Refugio Norte');
      final again = await node.joinChannel(name: 'refugio norte');
      expect(again!.id, first!.id);
      expect(node.channels, hasLength(1));

      await node.sendNamedChannelMessage(first, 'Llegamos 4');
      expect(node.messagesFor(first.peerId), hasLength(1));

      final snapshot = await StateStore(directory: directory).load();
      expect(snapshot!.channels.single.name, 'Refugio Norte');

      await node.leaveChannel(first.id);
      expect(node.channels, isEmpty);
      expect(node.messagesFor(first.peerId), isEmpty);
    });

    test('un mensaje de canal sale por el enlace y queda en cola', () async {
      transport.connect('link-1');
      final channel = (await node.joinChannel(name: 'Edificio B'))!;
      await node.sendNamedChannelMessage(channel, 'Cortaron la luz');
      final frame = MeshFrame.decode(transport.sent.last);
      expect(frame.type, FrameType.channelNamed);
      expect(frame.payload.sublist(0, 8), channel.idBytes);
      expect(node.pendingCount, 1);
    });

    test('un nombre inválido no crea nada', () async {
      expect(await node.joinChannel(name: ' '), isNull);
      expect(node.channels, isEmpty);
    });
  });

  group('nombre obligatorio al instalar', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('chasqui_setup_test');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('un estado viejo con nombre propio no vuelve a pedirlo', () {
      final snapshot = AppSnapshot.fromJson(<String, dynamic>{
        'name': 'Ana',
        'key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'messages': <dynamic>[],
        'peers': <dynamic>[],
        'outbox': <dynamic>[],
        'mode': 'equilibrado',
        'demo': false,
      });
      expect(snapshot.setupDone, isTrue);
    });

    test('el estado por defecto ("Yo") sí lo pide', () {
      final snapshot = AppSnapshot.fromJson(<String, dynamic>{
        'name': 'Yo',
        'key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'messages': <dynamic>[],
        'peers': <dynamic>[],
        'outbox': <dynamic>[],
        'mode': 'equilibrado',
        'demo': false,
      });
      expect(snapshot.setupDone, isFalse);
    });

    test('completar la bienvenida guarda el nombre y no se repite', () async {
      final transport = FakeTransport();
      final node = MeshNode(
        identity: await NodeIdentity.generate(),
        store: StateStore(directory: directory),
        transport: transport,
        monitorBattery: false,
        setupDone: false,
      );
      expect(node.needsSetup, isTrue);
      await node.completeSetup('  Ana   Gómez ');
      expect(node.needsSetup, isFalse);
      expect(node.displayName, 'Ana Gómez');

      final snapshot = await StateStore(directory: directory).load();
      expect(snapshot!.displayName, 'Ana Gómez');
      expect(snapshot.setupDone, isTrue);
      await transport.close();
      node.dispose();
    });
  });
}
