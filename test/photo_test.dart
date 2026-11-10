import 'dart:io';
import 'dart:typed_data';

import 'package:chasqui/src/core/frame.dart';
import 'package:chasqui/src/core/identity.dart';
import 'package:chasqui/src/core/models.dart';
import 'package:chasqui/src/core/photo.dart';
import 'package:chasqui/src/data/photo_store.dart';
import 'package:chasqui/src/data/state_store.dart';
import 'package:chasqui/src/mesh/mesh_node.dart';
import 'package:chasqui/src/mesh/router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

Uint8List fakeJpeg(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31 + 7) % 256;
  }
  return bytes;
}

void main() {
  group('trozos de foto', () {
    test('una foto se parte y se vuelve a armar igual', () {
      final jpeg = fakeJpeg(10000);
      final parts = PhotoChunker.split(fakeJpeg(16), jpeg);
      expect(parts, hasLength(4));
      final rebuilt = <int>[];
      for (final part in parts) {
        final parsed = PhotoChunker.parse(PhotoChunker.encode(part));
        expect(parsed, isNotNull);
        rebuilt.addAll(parsed!.data);
      }
      expect(rebuilt, jpeg);
    });

    test('una foto más grande que el tope ni se intenta', () {
      expect(
        () => PhotoChunker.split(fakeJpeg(16), fakeJpeg(PhotoChunker.maxPhotoBytes + 1)),
        throwsArgumentError,
      );
    });

    test('un trozo roto o con índices imposibles se descarta', () {
      expect(PhotoChunker.parse(Uint8List(5)), isNull);
      final broken = Uint8List(PhotoChunker.headerBytes + 4);
      broken[PhotoChunker.pidLength] = 3; // índice
      broken[PhotoChunker.pidLength + 1] = 2; // total menor que el índice
      expect(PhotoChunker.parse(broken), isNull);
    });
  });

  group('reensamblado', () {
    test('llegan en desorden y aun así se arma', () {
      final assembler = PhotoAssembler();
      final jpeg = fakeJpeg(9000);
      final parts = PhotoChunker.split(fakeJpeg(16), jpeg);
      final shuffled = [parts[2], parts[0], parts[1]];
      AssembledPhoto? done;
      for (final part in shuffled) {
        done = assembler.add('ana', part) ?? done;
      }
      expect(done, isNotNull);
      expect(done!.bytes, jpeg);
      expect(assembler.pendingCount, 0);
    });

    test('un trozo repetido no cuenta dos veces', () {
      final assembler = PhotoAssembler();
      final parts = PhotoChunker.split(fakeJpeg(16), fakeJpeg(4000));
      expect(assembler.add('ana', parts[0]), isNull);
      expect(assembler.add('ana', parts[0]), isNull);
      expect(assembler.missing('ana', parts[0].pidHex), 1);
    });

    test('fotos separadas de dos emisores no se mezclan', () {
      final assembler = PhotoAssembler();
      final pid = fakeJpeg(16);
      final parts = PhotoChunker.split(pid, fakeJpeg(4000));
      expect(assembler.add('ana', parts[0]), isNull);
      expect(assembler.add('beto', parts[1]), isNull);
      expect(assembler.missing('ana', parts[0].pidHex), 1);
      expect(assembler.missing('beto', parts[0].pidHex), 1);
    });
  });

  group('foto por la malla', () {
    test('se entrega completa, se confirma y no se repite al emisor', () async {
      final alice = await NodeIdentity.generate();
      final bob = await NodeIdentity.generate();
      final bus = _Bus();

      final aliceRouter = MeshRouter(
        identity: alice,
        broadcast: (frame, {exceptLink}) async {
          await bus.deliver(frame, from: alice.id);
        },
      );
      Uint8List? received;
      final acks = <MeshFrame>[];
      final bobRouter = MeshRouter(
        identity: bob,
        broadcast: (frame, {exceptLink}) async {
          if (frame.type == FrameType.ack) acks.add(frame);
          await bus.deliver(frame, from: bob.id);
        },
        onPhoto: (from, pidHex, bytes) => received = bytes,
      );
      bus
        ..register(aliceRouter)
        ..register(bobRouter);
      await bus.deliver(aliceRouter.presenceFrame('Ana'), from: alice.id);
      await bus.deliver(bobRouter.presenceFrame('Beto'), from: bob.id);

      final jpeg = fakeJpeg(9500);
      final parts = PhotoChunker.split(fakeJpeg(16), jpeg);
      for (final part in parts.reversed) {
        final frame = await aliceRouter.buildPhotoFrame(
          peer: aliceRouter.peers[bob.id]!,
          part: part,
        );
        await bobRouter.handlePacket(frame.encode(), linkId: 'link:ana');
      }

      expect(received, isNotNull);
      expect(received, jpeg);

      // La confirmación lleva el id de la foto entera: la burbuja del emisor
      // pasa a "entregado" cuando la imagen se pudo armar, no antes.
      expect(acks, hasLength(1));
      expect(acks.single.payload.sublist(0, 16), parts.first.pid);
    });

    test('un trozo que no es para mí se reenvía sin poder leerlo', () async {
      final alice = await NodeIdentity.generate();
      final bob = await NodeIdentity.generate();
      final carol = await NodeIdentity.generate();
      final relays = <MeshFrame>[];
      final courier = MeshRouter(
        identity: bob,
        broadcast: (frame, {exceptLink}) async => relays.add(frame),
      );
      final aliceRouter = MeshRouter(
        identity: alice,
        broadcast: (frame, {exceptLink}) async {},
      );
      final part = PhotoChunker.split(fakeJpeg(16), fakeJpeg(3000)).single;
      final frame = await aliceRouter.buildPhotoFrame(
        peer: PeerRecord(
          id: carol.id,
          name: 'Carla',
          publicKey: carol.publicKeyBytes,
          lastSeen: DateTime.now(),
        ),
        part: part,
      );
      await courier.handlePacket(frame.encode(), linkId: 'link:ana');
      expect(courier.relayed, 1);
      expect(relays.single.type, FrameType.photo);
    });
  });

  group('foto en el nodo', () {
    late Directory directory;
    late FakeTransport transport;
    late MeshNode node;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('chasqui_photo_test');
      transport = FakeTransport();
      node = MeshNode(
        identity: await NodeIdentity.generate(),
        store: StateStore(directory: directory),
        transport: transport,
        monitorBattery: false,
        photoStore: PhotoStore(directory: directory),
      );
      await node.start();
    });

    tearDown(() async {
      await transport.close();
      node.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('manda la foto en trozos y la deja en el historial', () async {
      transport.connect('link-1');
      // El nodo necesita conocer al destinatario (lo haría la presencia).
      final peerId = node.identity.id;
      expect(await node.sendPhoto(peerId, fakeJpeg(7000)), isFalse);

      final other = await NodeIdentity.generate();
      final peer = PeerRecord(
        id: other.id,
        name: 'Beto',
        publicKey: other.publicKeyBytes,
        lastSeen: DateTime.now(),
      );
      node.restore(
        AppSnapshot(
          displayName: 'Ana',
          privateKey: node.identity.privateKeyBytes,
          messages: const [],
          peers: [peer],
          outbox: const [],
          radioMode: node.radioMode,
          useDemo: false,
        ),
      );

      final ok = await node.sendPhoto(other.id, fakeJpeg(7000));
      expect(ok, isTrue);
      final check = node.messagesFor(other.id).single;
      expect(check.kind, MessageKind.photo);
      expect(check.photo, isNotNull);
      expect(await node.photoBytes(check.photo), fakeJpeg(7000));

      final frames = transport.sent.map(MeshFrame.decode).toList();
      final photos = frames.where((f) => f.type == FrameType.photo).toList();
      expect(photos, hasLength(3));
      expect(node.pendingCount, 3);
    });

    test('una foto demasiado grande se rechaza antes de gastar radio', () async {
      final other = await NodeIdentity.generate();
      node.restore(
        AppSnapshot(
          displayName: 'Ana',
          privateKey: node.identity.privateKeyBytes,
          messages: const [],
          peers: [
            PeerRecord(
              id: other.id,
              name: 'Beto',
              publicKey: other.publicKeyBytes,
              lastSeen: DateTime.now(),
            ),
          ],
          outbox: const [],
          radioMode: node.radioMode,
          useDemo: false,
        ),
      );
      expect(
        await node.sendPhoto(
          other.id,
          fakeJpeg(PhotoChunker.maxPhotoBytes + 1),
        ),
        isFalse,
      );
      expect(node.messagesFor(other.id), isEmpty);
    });
  });
}

class _Bus {
  final Map<String, MeshRouter> routers = <String, MeshRouter>{};

  void register(MeshRouter router) => routers[router.identity.id] = router;

  Future<void> deliver(MeshFrame frame, {required String from}) async {
    for (final entry in routers.entries) {
      if (entry.key == from) continue;
      await entry.value.handlePacket(frame.encode(), linkId: 'link:$from');
    }
  }
}
