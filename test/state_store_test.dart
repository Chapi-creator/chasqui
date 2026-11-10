import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/core/bytes.dart';
import 'package:chasqui/src/core/frame.dart';
import 'package:chasqui/src/core/models.dart';
import 'package:chasqui/src/data/state_store.dart';
import 'package:chasqui/src/power/power_policy.dart';

AppSnapshot snapshot({String name = 'Ana'}) {
  final frame = MeshFrame(
    type: FrameType.message,
    id: randomBytes(16),
    source: randomBytes(8),
    destination: randomBytes(8),
    timestamp: 1700000000000,
    payload: randomBytes(24),
  );
  return AppSnapshot(
    displayName: name,
    privateKey: Uint8List.fromList(randomBytes(32)),
    messages: [
      ChatMessage(
        id: 'msg-1',
        peerId: 'peer-1',
        outgoing: true,
        text: 'hola desde el sótano',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: MessageStatus.sent,
        hops: 2,
      ),
    ],
    peers: [
      PeerRecord(
        id: 'peer-1',
        name: 'Beto',
        publicKey: Uint8List.fromList(randomBytes(32)),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    ],
    outbox: [
      {'b': base64Encode(frame.encode()), 'q': 1700000000000},
    ],
    radioMode: RadioMode.ahorro,
    useDemo: true,
  );
}

void main() {
  late Directory directory;
  late StateStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chasqui_store_test');
    store = StateStore(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('guarda y recupera el estado completo', () async {
    final original = snapshot();
    await store.save(original);

    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.displayName, 'Ana');
    expect(loaded.privateKey, original.privateKey);
    expect(loaded.messages.single.text, 'hola desde el sótano');
    expect(loaded.messages.single.status, MessageStatus.sent);
    expect(loaded.messages.single.hops, 2);
    expect(loaded.peers.single.name, 'Beto');
    expect(loaded.outbox.single, original.outbox.single);
    expect(loaded.radioMode, RadioMode.ahorro);
    expect(loaded.useDemo, isTrue);
  });

  test('sobrescribir no deja restos ni rompe el archivo', () async {
    await store.save(snapshot(name: 'Ana'));
    await store.save(snapshot(name: 'Ana María'));

    final loaded = await store.load();
    expect(loaded!.displayName, 'Ana María');

    final files = directory.listSync().map((e) => e.path).toList();
    expect(files, hasLength(1), reason: 'no debe quedar el .tmp');
    expect(files.single, endsWith('chasqui_state.json'));
  });

  test('guardados simultáneos no dejan el archivo roto ni el .tmp', () async {
    // El temporizador de 2 s y un cierre de la app pueden escribir a la vez:
    // con un solo archivo temporal eso truncaba el JSON o rompía el rename.
    await Future.wait(
      List.generate(25, (i) => store.save(snapshot(name: 'nodo-$i'))),
    );

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.displayName, startsWith('nodo-'));
    expect(loaded.privateKey, hasLength(32));

    final files = directory.listSync().map((e) => e.path).toList();
    expect(files, hasLength(1), reason: 'no debe quedar el .tmp');
  });

  test('un archivo corrupto se detecta en vez de explotar', () async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}chasqui_state.json',
    );
    await file.writeAsString('{"v": 1, "name": ');

    expect(await store.load(), isNull);
  });

  test('acepta la cola del formato antiguo (base64 suelto)', () async {
    final frame = MeshFrame(
      type: FrameType.message,
      id: randomBytes(16),
      source: randomBytes(8),
      destination: randomBytes(8),
      timestamp: 1700000000000,
      payload: randomBytes(8),
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}chasqui_state.json',
    );
    await file.writeAsString(
      jsonEncode({
        'v': 1,
        'name': 'Viejo',
        'key': base64Encode(randomBytes(32)),
        'messages': <dynamic>[],
        'peers': <dynamic>[],
        'outbox': [base64Encode(frame.encode())],
        'mode': 'rapido',
        'demo': false,
      }),
    );

    final loaded = await store.load();

    expect(loaded!.outbox, hasLength(1));
    expect(loaded.outbox.single['b'], base64Encode(frame.encode()));
    expect(loaded.radioMode, RadioMode.rapido);
  });
}
