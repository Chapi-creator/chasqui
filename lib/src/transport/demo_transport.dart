import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/bytes.dart';
import '../core/channel.dart';
import '../core/crypto.dart';
import '../core/frame.dart';
import '../core/identity.dart';
import 'transport.dart';

/// Radio simulada para probar la app en un emulador o sin vecinos cerca.
///
/// Habla el protocolo real: sus nodos tienen claves X25519, cifran y descifran,
/// confirman entregas y responden. La única diferencia es que el "aire" es un
/// temporizador en lugar de Bluetooth.
class DemoMeshTransport implements MeshTransport {
  DemoMeshTransport({required this.owner});

  final NodeIdentity owner;

  final StreamController<InboundPacket> _inbound =
      StreamController<InboundPacket>.broadcast();
  final StreamController<LinkEvent> _linkEvents =
      StreamController<LinkEvent>.broadcast();

  final List<Timer> _timers = <Timer>[];
  final Map<String, _DemoPeer> _peers = <String, _DemoPeer>{};

  /// Semillas fijas: si los nodos simulados cambiaran de identidad en cada
  /// arranque, la lista de contactos se llenaría de Anas y Brunos fantasma
  /// que nunca vuelven a aparecer.
  static final Uint8List _anaSeed =
      Uint8List.fromList(List<int>.filled(32, 0x11));
  static final Uint8List _brunoSeed =
      Uint8List.fromList(List<int>.filled(32, 0x22));

  bool _running = false;
  int _replyIndex = 0;

  static const List<String> _replies = [
    'Recibido. Aquí no hay señal, pero tu mensaje llegó por la malla.',
    'Confirmado, estoy a un salto. Si te alejas, el mensaje se guarda y te llega luego.',
    'El nodo repetidor del centro reenvía bien. Ahorra batería y desconecta cuando no escribas.',
    'Perfecto. Estoy en modo ahorro: solo escucho 3 s cada 2 minutos.',
  ];

  @override
  Stream<InboundPacket> get inbound => _inbound.stream;

  @override
  Stream<LinkEvent> get linkEvents => _linkEvents.stream;

  @override
  int get connectedLinks => _running ? _peers.length : 0;

  @override
  bool get available => true;

  @override
  String get label => 'Malla simulada (demo)';

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;

    final ana = _DemoPeer(
      identity: await NodeIdentity.fromPrivateKey(_anaSeed),
      name: 'Ana',
      linkId: 'demo-ana',
      hops: 1,
    );
    final bruno = _DemoPeer(
      identity: await NodeIdentity.fromPrivateKey(_brunoSeed),
      name: 'Bruno (repetidor)',
      linkId: 'demo-bruno',
      hops: 2,
    );
    _peers[ana.identity.id] = ana;
    _peers[bruno.identity.id] = bruno;

    _later(const Duration(milliseconds: 500), () {
      _linkEvents.add(LinkEvent(linkId: ana.linkId, connected: true, rssi: -58));
      _announce(ana);
    });
    _later(const Duration(milliseconds: 1200), () {
      _linkEvents.add(LinkEvent(linkId: bruno.linkId, connected: true, rssi: -74));
      _announce(bruno);
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _peers.clear();
  }

  @override
  Future<void> send(
    Uint8List frame, {
    String? onlyLink,
    String? exceptLink,
  }) async {
    if (!_running) return;
    MeshFrame decoded;
    try {
      decoded = MeshFrame.decode(frame);
    } catch (_) {
      return;
    }
    if (decoded.type == FrameType.channel) {
      // El canal abierto también se responde en la demo, para que se pueda
      // probar SOS y estados sin dos teléfonos.
      final ana = _peers.isEmpty ? null : _peers.values.first;
      if (ana != null) {
        _later(
          const Duration(milliseconds: 700),
          () => _sendChannelReply(ana, decoded),
        );
      }
      return;
    }
    if (decoded.type != FrameType.message) return;
    final peer = _peers[decoded.destinationHex];
    if (peer == null) return;
    // Como en BLE, "excepto este enlace" silencia solo ese enlace, no todos:
    // antes se descartaba el reenvío entero y la demo no imitaba a la radio.
    if (onlyLink != null && onlyLink != peer.linkId) return;
    if (exceptLink != null && exceptLink == peer.linkId) return;

    _later(const Duration(milliseconds: 350), () => _sendAck(peer, decoded.id));
    _later(
      Duration(milliseconds: 1100 + (_replyIndex % 3) * 300),
      () => _sendReply(peer, decoded),
    );
  }

  @override
  void setDiscoveryEnabled(bool enabled) {
    // La demo no gasta radio: no hay nada que apagar.
  }

  void _announce(_DemoPeer peer) {
    final frame = MeshFrame.presence(
      source: Uint8List.fromList(peer.identity.nodeId),
      publicKey: peer.identity.publicKey,
      name: peer.name,
      ttl: 1,
      hops: peer.hops,
    );
    _emit(peer.linkId, frame);
  }

  void _sendAck(_DemoPeer peer, Uint8List originalId) {
    final frame = MeshFrame(
      type: FrameType.ack,
      id: randomBytes(16),
      source: Uint8List.fromList(peer.identity.nodeId),
      destination: Uint8List.fromList(owner.nodeId),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Uint8List.fromList(originalId),
      ttl: 3,
      hops: peer.hops,
    );
    _emit(peer.linkId, frame);
  }

  Future<void> _sendReply(_DemoPeer peer, MeshFrame incoming) async {
    final text = _replies[_replyIndex % _replies.length];
    _replyIndex += 1;
    final skeleton = MeshFrame(
      type: FrameType.message,
      id: randomBytes(16),
      source: Uint8List.fromList(peer.identity.nodeId),
      destination: Uint8List.fromList(owner.nodeId),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Uint8List(0),
      ttl: 3,
      hops: peer.hops,
    );
    final sealed = await MeshCrypto.seal(
      me: peer.identity,
      peer: owner.publicKey,
      plaintext: utf8.encode(text),
      aad: skeleton.authenticatedHeader(),
    );
    final frame = MeshFrame(
      type: FrameType.message,
      id: skeleton.id,
      source: skeleton.source,
      destination: skeleton.destination,
      timestamp: skeleton.timestamp,
      payload: sealed,
      ttl: 3,
      hops: peer.hops,
    );
    debugPrint(
      'Demo: respuesta de ${peer.name} a ${toHex(incoming.id).substring(0, 8)}',
    );
    _emit(peer.linkId, frame);
  }

  /// Respuesta de Ana en el canal abierto.
  Future<void> _sendChannelReply(_DemoPeer peer, MeshFrame incoming) async {
    final text = 'Aviso recibido en el canal (demo). Sigo aquí.';
    final skeleton = MeshFrame(
      type: FrameType.channel,
      id: randomBytes(16),
      source: Uint8List.fromList(peer.identity.nodeId),
      destination: MeshFrame.broadcastId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Uint8List(0),
      ttl: 1,
      hops: peer.hops,
    );
    final sealed = await ChannelCrypto.seal(
      plaintext: ChannelMessage(name: peer.name, text: text).encode(),
      aad: skeleton.authenticatedHeader(),
    );
    _emit(
      peer.linkId,
      MeshFrame(
        type: FrameType.channel,
        id: skeleton.id,
        source: skeleton.source,
        destination: skeleton.destination,
        timestamp: skeleton.timestamp,
        payload: sealed,
        ttl: 1,
        hops: peer.hops,
      ),
    );
  }

  void _emit(String linkId, MeshFrame frame) {
    if (!_running) return;
    _inbound.add(InboundPacket(linkId, frame.encode()));
  }

  void _later(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      // Si no se quita, la lista crece sin parar en sesiones largas.
      _timers.remove(timer);
      if (_running) action();
    });
    _timers.add(timer);
  }
}

class _DemoPeer {
  _DemoPeer({
    required this.identity,
    required this.name,
    required this.linkId,
    required this.hops,
  });

  final NodeIdentity identity;
  final String name;
  final String linkId;
  final int hops;
}
