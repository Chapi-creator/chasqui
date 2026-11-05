import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/core/bytes.dart';
import 'package:sinred/src/core/crypto.dart';
import 'package:sinred/src/core/frame.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/mesh/dedup_cache.dart';

void main() {
  group('tramas', () {
    test('codificar y decodificar conserva todos los campos', () async {
      final source = await NodeIdentity.generate();
      final frame = MeshFrame(
        type: FrameType.message,
        id: randomBytes(16),
        source: source.nodeId,
        destination: fromHex('0102030405060708'),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: Uint8List.fromList(utf8.encode('hola malla')),
        ttl: 3,
        hops: 1,
      );

      final decoded = MeshFrame.decode(frame.encode());

      expect(decoded.type, FrameType.message);
      expect(decoded.idHex, frame.idHex);
      expect(decoded.sourceHex, frame.sourceHex);
      expect(decoded.destinationHex, frame.destinationHex);
      expect(decoded.timestamp, frame.timestamp);
      expect(utf8.decode(decoded.payload), 'hola malla');
      expect(decoded.ttl, 3);
      expect(decoded.hops, 1);
    });

    test('reenviar baja el TTL y sube el contador de saltos', () async {
      final source = await NodeIdentity.generate();
      final frame = MeshFrame(
        type: FrameType.message,
        id: randomBytes(16),
        source: source.nodeId,
        destination: MeshFrame.broadcastId,
        timestamp: 1,
        payload: randomBytes(8),
        ttl: 3,
      );

      final forwarded = frame.forwarded();

      expect(forwarded.ttl, 2);
      expect(forwarded.hops, 1);
      expect(forwarded.idHex, frame.idHex);
      expect(frame.ttl, 3, reason: 'la original no debe mutar');
    });

    test('una trama truncada se rechaza en vez de explotar', () {
      expect(
        () => MeshFrame.decode(randomBytes(10)),
        throwsA(isA<FormatException>()),
      );
    });

    test('un nombre con acentos y emoji viaja intacto', () async {
      final id = await NodeIdentity.generate();
      final name = 'Ñandú 📡';
      final frame = MeshFrame.presence(
        source: id.nodeId,
        publicKey: id.publicKey,
        name: name,
      );

      final decoded = MeshFrame.decode(frame.encode());

      expect(decoded.payload[0], utf8.encode(name).length);
      expect(utf8.decode(decoded.payload.sublist(33)), name);
    });

    test('un nombre larguísimo se recorta sin partir un emoji', () async {
      final id = await NodeIdentity.generate();
      final frame = MeshFrame.presence(
        source: id.nodeId,
        publicKey: id.publicKey,
        name: '${'a' * 45}📡📡',
      );

      final nameBytes = frame.payload.sublist(33);

      expect(nameBytes.length, lessThanOrEqualTo(MeshFrame.maxNameBytes));
      // Si el recorte partiera el emoji, esto lanzaría FormatException.
      expect(() => utf8.decode(nameBytes), returnsNormally);
      expect(utf8.decode(nameBytes), 'a' * 45);
    });

    test('los anuncios de presencia llevan clave y nombre', () async {
      final id = await NodeIdentity.generate();
      final frame = MeshFrame.presence(
        source: id.nodeId,
        publicKey: id.publicKey,
        name: 'Ana',
      );

      final decoded = MeshFrame.decode(frame.encode());
      expect(decoded.type, FrameType.presence);
      expect(decoded.payload[0], 3); // longitud del nombre
      expect(utf8.decode(decoded.payload.sublist(33)), 'Ana');
      expect(decoded.payload.sublist(1, 33), id.publicKey.bytes);
    });
  });

  group('cifrado', () {
    test('solo el destinatario puede abrir el sobre', () async {
      final alice = await NodeIdentity.generate();
      final bob = await NodeIdentity.generate();
      final eve = await NodeIdentity.generate();

      final aad = randomBytes(33);
      final sealed = await MeshCrypto.seal(
        me: alice,
        peer: bob.publicKey,
        plaintext: utf8.encode('nos vemos en el punto'),
        aad: aad,
      );

      final clear = await MeshCrypto.open(
        me: bob,
        peer: alice.publicKey,
        sealed: sealed,
        aad: aad,
      );
      expect(utf8.decode(clear), 'nos vemos en el punto');

      expect(
        () => MeshCrypto.open(
          me: eve,
          peer: alice.publicKey,
          sealed: sealed,
          aad: aad,
        ),
        throwsA(anything),
      );
    });

    test('si cambia la cabecera autenticada, falla la apertura', () async {
      final alice = await NodeIdentity.generate();
      final bob = await NodeIdentity.generate();

      final sealed = await MeshCrypto.seal(
        me: alice,
        peer: bob.publicKey,
        plaintext: utf8.encode('mensaje'),
        aad: randomBytes(33),
      );

      expect(
        () => MeshCrypto.open(
          me: bob,
          peer: alice.publicKey,
          sealed: sealed,
          aad: randomBytes(33),
        ),
        throwsA(anything),
      );
    });

    test('la identidad es estable y su id deriva de la clave pública',
        () async {
      final original = await NodeIdentity.generate();
      final restored =
          await NodeIdentity.fromPrivateKey(original.privateKeyBytes);

      expect(restored.id, original.id);
      expect(
        await NodeIdentity.matchesNodeId(restored.publicKeyBytes, restored.nodeId),
        isTrue,
      );
      expect(
        await NodeIdentity.matchesNodeId(
          (await NodeIdentity.generate()).publicKeyBytes,
          restored.nodeId,
        ),
        isFalse,
      );
    });
  });

  test('la caché de deduplicación ignora repetidos y caduca', () {
    final cache = DedupCache(ttl: const Duration(seconds: 10));
    final now = DateTime(2026, 1, 1, 12);

    expect(cache.markSeen('a', now: now), isTrue);
    expect(cache.markSeen('a', now: now), isFalse);
    expect(cache.length, 1);

    expect(
      cache.markSeen('a', now: now.add(const Duration(minutes: 1))),
      isTrue,
      reason: 'pasado el TTL vuelve a aceptarse',
    );
  });
}
