import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/core/bytes.dart';
import 'package:sinred/src/core/contact_code.dart';
import 'package:sinred/src/core/frame.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/core/models.dart';
import 'package:sinred/src/data/state_store.dart';
import 'package:sinred/src/mesh/mesh_node.dart';
import 'package:sinred/src/power/power_policy.dart';

import 'support/fake_transport.dart';

void main() {
  group('código de invitación', () {
    test('ida y vuelta conserva id, clave y nombre', () async {
      final other = await NodeIdentity.generate();
      final invite = ContactInvite(
        nodeId: other.id,
        publicKey: other.publicKeyBytes,
        name: 'Ana Gómez',
      );

      final decoded = ContactInvite.decode(invite.encode());

      expect(decoded, isNotNull);
      expect(decoded!.nodeId, other.id);
      expect(decoded.publicKey, other.publicKeyBytes);
      expect(decoded.name, 'Ana Gómez');
      expect(await decoded.verify(), isTrue);
    });

    test('tolera espacios y saltos de línea al pegar', () async {
      final other = await NodeIdentity.generate();
      final code = ContactInvite(
        nodeId: other.id,
        publicKey: other.publicKeyBytes,
        name: 'Bruno',
      ).encode();

      final messy = '  ${code.substring(0, 10)}\n${code.substring(10)}  ';

      expect(ContactInvite.decode(messy)?.nodeId, other.id);
    });

    test('rechaza texto que no es un código de SinRed', () {
      expect(ContactInvite.decode('https://ejemplo.com'), isNull);
      expect(ContactInvite.decode('SINRED1:1234:abcd:zzz'), isNull);
      expect(ContactInvite.decode(''), isNull);
    });

    test('detecta una clave que no corresponde al id (suplantación)', () async {
      final real = await NodeIdentity.generate();
      final impostor = await NodeIdentity.generate();
      final fake = ContactInvite(
        nodeId: real.id,
        publicKey: impostor.publicKeyBytes,
        name: 'Ana',
      );

      expect(await fake.verify(), isFalse);
    });

    test('recorta nombres largos sin partir caracteres', () {
      final clamped = ContactInvite.clampName('a' * 80);
      expect(clamped.length, ContactInvite.maxNameBytes);

      final emoji = ContactInvite.clampName('🙂' * 40);
      expect(emoji.runes.length, lessThanOrEqualTo(12));
    });
  });

  group('libreta de contactos', () {
    late Directory directory;
    late NodeIdentity identity;
    late FakeTransport transport;
    late StateStore store;
    late MeshNode node;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sinred_contacts');
      identity = await NodeIdentity.generate();
      transport = FakeTransport();
      store = StateStore(directory: directory);
      node = MeshNode(
        identity: identity,
        store: store,
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

    Future<ContactInvite> inviteFor(String name) async {
      final other = await NodeIdentity.generate();
      return ContactInvite(
        nodeId: other.id,
        publicKey: other.publicKeyBytes,
        name: name,
      );
    }

    test('agrega el contacto y sobrevive a reabrir la app', () async {
      final invite = await inviteFor('Ana');

      expect(await node.addContact(invite.encode()), AddContactResult.added);
      expect(node.contacts.single.name, 'Ana');
      expect(node.isContact(invite.nodeId), isTrue);

      // Otro arranque leyendo el mismo archivo: el contacto sigue ahí.
      final snapshot = await store.load();
      expect(snapshot, isNotNull);
      final reopened = MeshNode(
        identity: identity,
        store: store,
        transport: FakeTransport(),
        monitorBattery: false,
      );
      reopened.restore(snapshot!);

      expect(reopened.contacts.single.id, invite.nodeId);
      expect(reopened.contacts.single.name, 'Ana');
      reopened.dispose();
    });

    test('no duplica un contacto ya guardado', () async {
      final invite = await inviteFor('Ana');

      expect(await node.addContact(invite.encode()), AddContactResult.added);
      expect(await node.addContact(invite.encode()), AddContactResult.already);
      expect(node.contacts.length, 1);
    });

    test('rechaza el código del propio teléfono y los dañados', () async {
      final mine = ContactInvite(
        nodeId: identity.id,
        publicKey: identity.publicKeyBytes,
        name: 'Yo',
      );
      expect(await node.addContact(mine.encode()), AddContactResult.ownCode);

      final real = await NodeIdentity.generate();
      final impostor = await NodeIdentity.generate();
      final tampered = ContactInvite(
        nodeId: real.id,
        publicKey: impostor.publicKeyBytes,
        name: 'Ana',
      );
      expect(await node.addContact(tampered.encode()), AddContactResult.invalid);
      expect(node.contacts, isEmpty);
    });

    test('quitar de contactos no borra el historial del nodo', () async {
      final invite = await inviteFor('Ana');
      await node.addContact(invite.encode());

      node.removeContact(invite.nodeId);

      expect(node.contacts, isEmpty);
      expect(node.peer(invite.nodeId), isNotNull);
    });

    test('avisa una sola vez cuando el contacto aparece al alcance', () async {
      final other = await NodeIdentity.generate();
      await node.addContact(ContactInvite(
        nodeId: other.id,
        publicKey: other.publicKeyBytes,
        name: 'Ana',
      ).encode());

      final events = <PeerRecord>[];
      final subscription = node.contactReachable.listen(events.add);

      transport.connect('link-1');
      await pumpEventQueue();
      transport.incoming(
        'link-1',
        MeshFrame.presence(
          source: other.nodeId,
          publicKey: other.publicKey,
          name: 'Ana',
        ).encode(),
      );
      await pumpEventQueue();

      expect(events.length, 1, reason: 'el aviso sale al aparecer');
      expect(events.single.id, other.id);
      expect(events.single.directLink, isTrue);

      // Otro anuncio del mismo nodo no repite la notificación.
      transport.incoming(
        'link-1',
        MeshFrame.presence(
          source: other.nodeId,
          publicKey: other.publicKey,
          name: 'Ana',
        ).encode(),
      );
      await pumpEventQueue();
      expect(events.length, 1);

      await subscription.cancel();
    });

    test('un nodo que no está en la libreta no genera avisos', () async {
      final other = await NodeIdentity.generate();
      final events = <PeerRecord>[];
      final subscription = node.contactReachable.listen(events.add);

      transport.connect('link-1');
      await pumpEventQueue();
      transport.incoming(
        'link-1',
        MeshFrame.presence(
          source: other.nodeId,
          publicKey: other.publicKey,
          name: 'Desconocido',
        ).encode(),
      );
      await pumpEventQueue();

      expect(events, isEmpty);
      await subscription.cancel();
    });
  });

  group('código corto', () {
    late Directory directory;
    late NodeIdentity identity;
    late FakeTransport transport;
    late StateStore store;
    late MeshNode node;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sinred_short_code');
      identity = await NodeIdentity.generate();
      transport = FakeTransport();
      store = StateStore(directory: directory);
      node = MeshNode(
        identity: identity,
        store: store,
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

    Future<void> announce(NodeIdentity other, {String name = 'Ana'}) async {
      transport.connect('link-1');
      await pumpEventQueue();
      transport.incoming(
        'link-1',
        MeshFrame.presence(
          source: other.nodeId,
          publicKey: other.publicKey,
          name: name,
        ).encode(),
      );
      await pumpEventQueue();
    }

    test('es estable, de 6 símbolos y sin letras confundibles', () async {
      final other = await NodeIdentity.generate();
      final code = contactCodeOf(other.id);

      expect(code, contactCodeOf(other.id));
      expect(code.length, 6);
      expect(RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code), isTrue,
          reason: 'sin 0/O ni 1/I');
      expect(formatContactCode(code), contains('-'));
      expect(
        normalizeContactCode(' ${formatContactCode(code).toLowerCase()} '),
        code,
        reason: 'acepta lo que la gente escribe',
      );
    });

    test('personas distintas tienen códigos distintos', () async {
      final codes = <String>{};
      for (var i = 0; i < 6; i++) {
        codes.add(contactCodeOf((await NodeIdentity.generate()).id));
      }
      expect(codes.length, 6);
    });

    test('agrega a un nodo que está en la malla', () async {
      final other = await NodeIdentity.generate();
      await announce(other);

      final code = contactCodeOf(other.id);
      expect(node.peerByContactCode(formatContactCode(code))?.id, other.id);

      expect(await node.addContactByCode(code), AddContactResult.added);
      expect(node.isContact(other.id), isTrue);
      expect(await node.addContactByCode(code), AddContactResult.already);

      // Y queda guardado, como el agregado por QR.
      final snapshot = await store.load();
      expect(snapshot!.peers.single.isContact, isTrue);
    });

    test('código propio, desconocido o mal formado', () async {
      expect(
        await node.addContactByCode(node.myContactCode),
        AddContactResult.ownCode,
      );
      expect(await node.addContactByCode('ZZZZZZ'), AddContactResult.notFound);
      expect(await node.addContactByCode('123'), AddContactResult.invalid);
      expect(node.contacts, isEmpty);
    });

    test('dos nodos con el mismo código: no adivina', () async {
      // Se buscan dos ids que compartan código corto (colisión real del
      // espacio de 30 bits) y se cargan como si ya hubieran aparecido.
      final byCode = <String, String>{};
      String? first;
      String? second;
      String? shared;
      while (shared == null) {
        final id = toHex(randomBytes(8));
        final code = contactCodeOf(id);
        final known = byCode[code];
        if (known != null && known != id) {
          shared = code;
          first = known;
          second = id;
          break;
        }
        byCode[code] = id;
      }

      final now = DateTime.now();
      node.restore(AppSnapshot(
        displayName: 'Yo',
        privateKey: identity.privateKeyBytes,
        messages: const [],
        peers: [
          PeerRecord(
            id: first!,
            name: 'Uno',
            publicKey: Uint8List(32),
            lastSeen: now,
          ),
          PeerRecord(
            id: second!,
            name: 'Dos',
            publicKey: Uint8List(32),
            lastSeen: now,
          ),
        ],
        outbox: const [],
        radioMode: RadioMode.equilibrado,
        useDemo: false,
      ));

      expect(await node.addContactByCode(shared), AddContactResult.ambiguous);
      expect(node.contacts, isEmpty);
    });
  });
}
