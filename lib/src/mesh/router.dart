import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../core/bytes.dart';
import '../core/channel.dart';
import '../core/crypto.dart';
import '../core/frame.dart';
import '../core/geo.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../core/named_channel.dart';
import '../core/photo.dart';
import 'dedup_cache.dart';
import 'outbox.dart';

typedef FrameBroadcaster =
    Future<void> Function(MeshFrame frame, {String? exceptLink});
typedef MessageReceived =
    Future<void> Function(PeerRecord from, String text, int hops);
typedef AckReceived = void Function(String frameKey, String fromPeerId);
typedef PresenceReceived = void Function(PeerRecord peer, String? linkId);
typedef LocationReceived =
    void Function(PeerRecord from, GeoPoint point, int hops);
typedef ChannelReceived =
    void Function(String sourceId, ChannelMessage message, int hops);
typedef NamedChannelReceived =
    void Function(
      String channelIdHex,
      String sourceId,
      ChannelMessage message,
      int hops,
    );

/// Busca la clave de un canal con nombre. Devuelve null si no es un canal de
/// este teléfono; en ese caso la trama ni se descifra ni se repite.
typedef NamedChannelKeyResolver =
    Future<SecretKey?> Function(String channelIdHex);
typedef PhotoReceived =
    void Function(PeerRecord from, String pidHex, Uint8List bytes);
typedef PhotoProgress =
    void Function(PeerRecord from, String pidHex, int missing);

/// Lógica de red pura (sin Bluetooth): decide qué hacer con cada trama.
///
/// Estrategia: inundación epidémica con TTL + deduplicación + reenvío diferido.
/// Es la misma familia que usa BitChat, pero con presupuesto de radio: cada
/// trama tiene TTL corto (3 saltos ≈ 300 m en cadena) y los nodos no repiten
/// lo que ya vieron.
class MeshRouter {
  MeshRouter({
    required this.identity,
    required this.broadcast,
    this.onMessage,
    this.onAck,
    this.onPresence,
    this.onLocation,
    this.onChannel,
    this.onNamedChannel,
    this.resolveNamedChannelKey,
    this.onPhoto,
    this.onPhotoProgress,
    this.maxPeers = 500,
    DedupCache? dedup,
    Outbox? outbox,
  }) : dedup = dedup ?? DedupCache(),
       outbox = outbox ?? Outbox();

  final NodeIdentity identity;
  final FrameBroadcaster broadcast;
  final MessageReceived? onMessage;
  final AckReceived? onAck;
  final PresenceReceived? onPresence;
  final LocationReceived? onLocation;
  final ChannelReceived? onChannel;
  final NamedChannelReceived? onNamedChannel;
  final NamedChannelKeyResolver? resolveNamedChannelKey;
  final PhotoReceived? onPhoto;
  final PhotoProgress? onPhotoProgress;

  /// Trozos de fotos que se están armando, por emisor.
  final PhotoAssembler photos = PhotoAssembler();

  /// Tramas de otros que este nodo reenvió (lo que la UI llama "repetidor").
  int relayed = 0;

  final DedupCache dedup;
  final Outbox outbox;
  final Map<String, PeerRecord> peers = <String, PeerRecord>{};

  /// Saltos que puede dar un chat privado antes de quedarse guardado.
  ///
  /// Con 3 saltos, una cadena de 4 teléfonos ya no pasaba: el mensaje moría a
  /// media calle. Además, al agotarse los saltos ya no se tira la trama: la
  /// guarda [Outbox] y la vuelve a soltar cuando encuentra a alguien (mensajero).
  static const int defaultTtl = 5;

  /// El canal abierto vive más saltos que un chat privado: en una catástrofe
  /// interesa que un aviso cruce toda la cadena disponible, no solo el vecino.
  static const int channelTtl = 7;

  /// Saltos con los que se reemite una trama acarreada al encontrar un nodo.
  static const int carryTtl = 2;

  SimplePublicKey publicKeyOf(PeerRecord peer) =>
      SimplePublicKey(peer.publicKey, type: KeyPairType.x25519);

  /// Anuncio de presencia (barato: ~50–90 bytes, solo al conectar).
  MeshFrame presenceFrame(String displayName) => MeshFrame.presence(
    source: Uint8List.fromList(identity.nodeId),
    publicKey: identity.publicKey,
    name: displayName,
  );

  Future<MeshFrame> buildMessageFrame({
    required PeerRecord peer,
    required String text,
  }) async {
    final id = randomBytes(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final skeleton = MeshFrame(
      type: FrameType.message,
      id: id,
      source: Uint8List.fromList(identity.nodeId),
      destination: Uint8List.fromList(fromHex(peer.id)),
      timestamp: now,
      payload: Uint8List(0),
      ttl: defaultTtl,
    );
    final sealed = await MeshCrypto.seal(
      me: identity,
      peer: publicKeyOf(peer),
      plaintext: utf8.encode(text),
      aad: skeleton.authenticatedHeader(),
    );
    return MeshFrame(
      type: FrameType.message,
      id: id,
      source: skeleton.source,
      destination: skeleton.destination,
      timestamp: now,
      payload: sealed,
      ttl: defaultTtl,
    );
  }

  /// Coordenadas cifradas para un contacto: quien repite no las puede leer.
  Future<MeshFrame> buildLocationFrame({
    required PeerRecord peer,
    required GeoPoint point,
  }) async {
    final id = randomBytes(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final skeleton = MeshFrame(
      type: FrameType.location,
      id: id,
      source: Uint8List.fromList(identity.nodeId),
      destination: Uint8List.fromList(fromHex(peer.id)),
      timestamp: now,
      payload: Uint8List(0),
      ttl: defaultTtl,
    );
    final sealed = await MeshCrypto.seal(
      me: identity,
      peer: publicKeyOf(peer),
      plaintext: point.encodePayload(),
      aad: skeleton.authenticatedHeader(),
    );
    return MeshFrame(
      type: FrameType.location,
      id: id,
      source: skeleton.source,
      destination: skeleton.destination,
      timestamp: now,
      payload: sealed,
      ttl: defaultTtl,
    );
  }

  /// Mensaje del canal abierto.
  ///
  /// Va a difusión (destino cero) y cifrado con la clave de grupo: no hay
  /// destinatario ni ACK. Cualquiera que lo reciba lo puede leer y reenviar.
  Future<MeshFrame> buildChannelFrame(ChannelMessage message) async {
    final id = randomBytes(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final skeleton = MeshFrame(
      type: FrameType.channel,
      id: id,
      source: Uint8List.fromList(identity.nodeId),
      destination: MeshFrame.broadcastId,
      timestamp: now,
      payload: Uint8List(0),
      ttl: channelTtl,
    );
    final sealed = await ChannelCrypto.seal(
      plaintext: message.encode(),
      aad: skeleton.authenticatedHeader(),
    );
    return MeshFrame(
      type: FrameType.channel,
      id: id,
      source: skeleton.source,
      destination: skeleton.destination,
      timestamp: now,
      payload: sealed,
      ttl: channelTtl,
    );
  }

  /// Mensaje de un canal con nombre.
  ///
  /// El payload lleva el id del canal (8 bytes) y el contenido cifrado con la
  /// clave derivada del nombre. El id va también en lo autenticado: sin eso,
  /// alguien podría cambiar la etiqueta del canal y hacer que el receptor
  /// busque otra clave.
  Future<MeshFrame> buildNamedChannelFrame({
    required NamedChannel channel,
    required SecretKey key,
    required ChannelMessage message,
  }) async {
    final id = randomBytes(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final channelId = channel.idBytes;
    final skeleton = MeshFrame(
      type: FrameType.channelNamed,
      id: id,
      source: Uint8List.fromList(identity.nodeId),
      destination: MeshFrame.broadcastId,
      timestamp: now,
      payload: Uint8List(0),
      ttl: channelTtl,
    );
    final sealed = await ChannelCrypto.seal(
      plaintext: message.encode(),
      aad: concatBytes([skeleton.authenticatedHeader(), channelId]),
      key: key,
    );
    final payload = Uint8List(8 + sealed.length);
    payload.setRange(0, 8, channelId);
    payload.setRange(8, payload.length, sealed);
    return MeshFrame(
      type: FrameType.channelNamed,
      id: id,
      source: skeleton.source,
      destination: skeleton.destination,
      timestamp: now,
      payload: payload,
      ttl: channelTtl,
    );
  }

  /// Trozo de foto cifrado para un contacto.
  ///
  /// Cada trozo es una trama independiente: tiene su propio id, su propia
  /// deduplicación y se reenvía solo si llega completo. Un enlace que se corta
  /// a mitad de la foto no tira lo que ya llegó.
  Future<MeshFrame> buildPhotoFrame({
    required PeerRecord peer,
    required PhotoPart part,
  }) async {
    final id = randomBytes(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final skeleton = MeshFrame(
      type: FrameType.photo,
      id: id,
      source: Uint8List.fromList(identity.nodeId),
      destination: Uint8List.fromList(fromHex(peer.id)),
      timestamp: now,
      payload: Uint8List(0),
      ttl: defaultTtl,
    );
    final sealed = await MeshCrypto.seal(
      me: identity,
      peer: publicKeyOf(peer),
      plaintext: PhotoChunker.encode(part),
      aad: skeleton.authenticatedHeader(),
    );
    return MeshFrame(
      type: FrameType.photo,
      id: id,
      source: skeleton.source,
      destination: skeleton.destination,
      timestamp: now,
      payload: sealed,
      ttl: defaultTtl,
    );
  }

  MeshFrame buildAckFrame(MeshFrame original) => MeshFrame(
    type: FrameType.ack,
    id: randomBytes(16),
    source: Uint8List.fromList(identity.nodeId),
    destination: Uint8List.fromList(original.source),
    timestamp: DateTime.now().millisecondsSinceEpoch,
    payload: Uint8List.fromList(original.id),
    // Un ACK tiene que llegar tan lejos como el mensaje que confirma.
    ttl: defaultTtl,
  );

  /// Procesa un paquete recibido por [linkId].
  Future<void> handlePacket(Uint8List bytes, {String? linkId}) async {
    MeshFrame frame;
    try {
      frame = MeshFrame.decode(bytes);
    } on FormatException catch (error) {
      debugPrint('Malla: trama inválida ($error)');
      return;
    }

    if (frame.sourceHex == identity.id) return; // bucle propio
    if (!_isFresh(frame)) return;

    // Mensaje para mí de un nodo que todavía no conozco: no lo marco como
    // visto. Si lo marcara, el reenvío del emisor (misma id de trama) se
    // descartaría para siempre y el mensaje nunca se entregaría cuando su
    // anuncio de presencia llegara unos milisegundos después.
    final isForMe =
        frame.destinationHex == identity.id &&
        !peers.containsKey(frame.sourceHex);
    if (isForMe &&
        (frame.type == FrameType.message || frame.type == FrameType.location)) {
      debugPrint('Malla: trama de nodo desconocido ${frame.sourceHex}');
      return;
    }

    if (!dedup.markSeen(frame.dedupKey)) return;

    switch (frame.type) {
      case FrameType.presence:
        await _handlePresence(frame, linkId);
      case FrameType.message:
        await _handleMessage(frame, linkId);
      case FrameType.ack:
        await _handleAck(frame, linkId);
      case FrameType.location:
        await _handleLocation(frame, linkId);
      case FrameType.channel:
        await _handleChannel(frame, linkId);
      case FrameType.channelNamed:
        await _handleNamedChannel(frame, linkId);
      case FrameType.photo:
        await _handlePhoto(frame, linkId);
    }
  }

  /// Trozo de foto. Se descifra solo si es para este nodo; si no, se reenvía
  /// como cualquier mensaje privado.
  Future<void> _handlePhoto(MeshFrame frame, String? linkId) async {
    if (frame.destinationHex == identity.id) {
      final peer = peers[frame.sourceHex];
      if (peer == null) return;
      try {
        final clear = await MeshCrypto.open(
          me: identity,
          peer: publicKeyOf(peer),
          sealed: frame.payload,
          aad: frame.authenticatedHeader(),
        );
        final part = PhotoChunker.parse(clear);
        if (part == null) {
          debugPrint('Malla: trozo de foto inválido');
          return;
        }
        final photo = photos.add(peer.id, part);
        if (photo == null) {
          onPhotoProgress?.call(
            peer,
            part.pidHex,
            photos.missing(peer.id, part.pidHex) ?? 0,
          );
          return;
        }
        peer.lastSeen = DateTime.now();
        onPhoto?.call(peer, photo.pidHex, photo.bytes);
        // Se confirma la foto entera, no cada trozo: el emisor marca la
        // burbuja como entregada solo cuando la imagen se pudo armar.
        await broadcast(
          MeshFrame(
            type: FrameType.ack,
            id: randomBytes(16),
            source: Uint8List.fromList(identity.nodeId),
            destination: Uint8List.fromList(fromHex(peer.id)),
            timestamp: DateTime.now().millisecondsSinceEpoch,
            payload: Uint8List.fromList(fromHex(photo.pidHex)),
            ttl: defaultTtl,
          ),
        );
      } catch (error) {
        debugPrint('Malla: no se pudo descifrar la foto (${error.runtimeType})');
      }
      return;
    }

    if (frame.ttl > 1) {
      relayed += 1;
      outbox.enqueueRelay(frame.forwarded());
      await broadcast(frame.forwarded(), exceptLink: linkId);
    } else {
      outbox.enqueueRelay(frame);
    }
  }

  /// Canal con nombre: solo se descifra y se repite si es un canal de este
  /// teléfono. Un nodo que no está en el canal no puede verificarlo, así que
  /// no lo repite: no tiene sentido inundar la malla con algo que nadie de
  /// alrededor puede leer.
  Future<void> _handleNamedChannel(MeshFrame frame, String? linkId) async {
    if (frame.payload.length < 8 + ChannelCrypto.nonceLength + ChannelCrypto.macLength + 1) {
      return;
    }
    final channelId = frame.payload.sublist(0, 8);
    final channelIdHex = toHex(channelId);
    final key = await resolveNamedChannelKey?.call(channelIdHex);
    if (key == null) return;

    var readable = false;
    try {
      final clear = await ChannelCrypto.open(
        sealed: frame.payload.sublist(8),
        aad: concatBytes([frame.authenticatedHeader(), channelId]),
        key: key,
      );
      final message = ChannelMessage.decode(clear);
      if (message == null) {
        debugPrint('Malla: mensaje de canal ilegible');
      } else {
        readable = true;
        onNamedChannel?.call(channelIdHex, frame.sourceHex, message, frame.hops);
      }
    } catch (error) {
      debugPrint('Malla: canal con nombre no se pudo descifrar (${error.runtimeType})');
    }

    if (!readable) return;

    if (frame.ttl > 1) {
      relayed += 1;
      outbox.enqueueRelay(frame.forwarded());
      await broadcast(frame.forwarded(), exceptLink: linkId);
    } else {
      outbox.enqueueRelay(frame);
    }
  }

  /// Canal abierto: se entrega siempre y se reenvía siempre (no hay destino
  /// que decidirlo). El emisor puede ser desconocido: en una emergencia el
  /// aviso de un desconocido sigue siendo útil.
  Future<void> _handleChannel(MeshFrame frame, String? linkId) async {
    var readable = false;
    try {
      final clear = await ChannelCrypto.open(
        sealed: frame.payload,
        aad: frame.authenticatedHeader(),
      );
      final message = ChannelMessage.decode(clear);
      if (message == null) {
        debugPrint('Malla: mensaje de canal ilegible');
      } else {
        readable = true;
        onChannel?.call(frame.sourceHex, message, frame.hops);
      }
    } catch (error) {
      debugPrint('Malla: canal no se pudo descifrar (${error.runtimeType})');
    }

    // Una trama que ni nosotros podemos descifrar (basura o manipulada) no se
    // repite: con TTL 5, reenviarla convertía cualquier ruido en una inundación
    // de toda la malla sin que nadie pudiera leerlo.
    if (!readable) return;

    if (frame.ttl > 1) {
      relayed += 1;
      outbox.enqueueRelay(frame.forwarded());
      await broadcast(frame.forwarded(), exceptLink: linkId);
    } else {
      // Sin saltos, se guarda para el siguiente que pase (mensajero).
      outbox.enqueueRelay(frame);
    }
  }

  Future<void> _handlePresence(MeshFrame frame, String? linkId) async {
    final peer = await _parsePresence(frame);
    if (peer == null) return;
    final existing = peers[peer.id];
    if (existing != null && !_sameKey(existing.publicKey, peer.publicKey)) {
      // TOFU: una clave distinta para el mismo id es una suplantación.
      debugPrint('Malla: clave distinta para ${peer.id}; anuncio ignorado');
      return;
    }
    if (existing == null) {
      peers[peer.id] = peer;
      _trimPeers();
    } else {
      existing
        ..name = peer.name
        ..lastSeen = peer.lastSeen
        ..hops = frame.hops;
    }
    onPresence?.call(peers[peer.id]!, linkId);
    if (frame.ttl > 1) {
      await broadcast(frame.forwarded(), exceptLink: linkId);
    }
  }

  Future<void> _handleMessage(MeshFrame frame, String? linkId) async {
    if (frame.destinationHex == identity.id) {
      final peer = peers[frame.sourceHex];
      if (peer == null) {
        debugPrint('Malla: mensaje de nodo desconocido ${frame.sourceHex}');
        return;
      }
      try {
        final clear = await MeshCrypto.open(
          me: identity,
          peer: publicKeyOf(peer),
          sealed: frame.payload,
          aad: frame.authenticatedHeader(),
        );
        // Un emisor podría mandar bytes que no son UTF-8 válido: no dejamos
        // que eso rompa la recepción.
        final text = utf8.decode(clear, allowMalformed: true);
        await onMessage?.call(peer, text, frame.hops);
        peer.lastSeen = DateTime.now();
        await broadcast(buildAckFrame(frame));
      } catch (error) {
        debugPrint('Malla: no se pudo descifrar (${error.runtimeType})');
      }
      return;
    }

    // Vamos de repetidor. Si ya no quedan saltos, la trama no se tira: se
    // queda en el bolsillo hasta que aparezca otro teléfono (mensajero). Así un
    // mensaje puede cruzar un pueblo entero en dos viajes, sin repetidores
    // fijos ni internet.
    if (frame.ttl > 1) {
      relayed += 1;
      outbox.enqueueRelay(frame.forwarded());
      await broadcast(frame.forwarded(), exceptLink: linkId);
    } else {
      outbox.enqueueRelay(frame);
    }
  }

  Future<void> _handleLocation(MeshFrame frame, String? linkId) async {
    if (frame.destinationHex == identity.id) {
      final peer = peers[frame.sourceHex];
      if (peer == null) return;
      try {
        final clear = await MeshCrypto.open(
          me: identity,
          peer: publicKeyOf(peer),
          sealed: frame.payload,
          aad: frame.authenticatedHeader(),
        );
        final point = GeoPoint.decodePayload(clear);
        // Coordenadas imposibles o truncadas: se ignoran sin romper la malla.
        if (point == null) {
          debugPrint('Malla: ubicación inválida de ${peer.id}');
          return;
        }
        peer.lastSeen = DateTime.now();
        onLocation?.call(peer, point, frame.hops);
      } catch (error) {
        debugPrint(
          'Malla: no se pudo descifrar la ubicación (${error.runtimeType})',
        );
      }
      return;
    }

    if (frame.ttl > 1) {
      relayed += 1;
      outbox.enqueueRelay(frame.forwarded());
      await broadcast(frame.forwarded(), exceptLink: linkId);
    } else {
      outbox.enqueueRelay(frame);
    }
  }

  Future<void> _handleAck(MeshFrame frame, String? linkId) async {
    if (frame.destinationHex == identity.id && frame.payload.length == 16) {
      // La clave del mensaje original la formó *mi* id + el id de la trama,
      // no el id de quien confirma.
      final originalKey = '${identity.id}:${toHex(frame.payload)}';
      outbox.remove(originalKey);
      onAck?.call(originalKey, frame.sourceHex);
      return;
    }
    if (frame.ttl > 1) {
      await broadcast(frame.forwarded(), exceptLink: linkId);
    }
  }

  /// Reenvía lo pendiente cuando aparece un enlace nuevo.
  Future<void> flushOnNewLink() async {
    for (final frame in outbox.relayFrames) {
      // Las acarreadas se reemiten con saltos frescos: si salieran con el TTL
      // que traían (0 o 1), el vecino las daría por agotadas y el acarreo no
      // serviría de nada. Las que aún tenían saltos conservan los suyos.
      final ttl = frame.ttl > carryTtl ? frame.ttl : carryTtl;
      await broadcast(frame.refreshed(ttl));
    }
    for (final entry in outbox.ownPending) {
      await broadcast(entry.frame);
    }
  }

  Future<PeerRecord?> _parsePresence(MeshFrame frame) async {
    if (frame.payload.length < 33) return null;
    final nameLength = frame.payload[0];
    if (frame.payload.length != 33 + nameLength) return null;
    final publicKey = frame.payload.sublist(1, 33);
    final name = utf8
        .decode(frame.payload.sublist(33), allowMalformed: true)
        .trim();
    if (name.isEmpty) return null;
    // El id debe ser el prefijo SHA-256 de la clave: evita suplantaciones.
    if (!await NodeIdentity.matchesNodeId(publicKey, frame.source)) {
      debugPrint('Malla: presencia con id/clave inconsistente');
      return null;
    }
    return PeerRecord(
      id: frame.sourceHex,
      name: name,
      publicKey: Uint8List.fromList(publicKey),
      lastSeen: DateTime.now(),
      hops: frame.hops,
    );
  }

  /// Tope de nodos guardados en memoria.
  ///
  /// En una plaza llena con la app abierta se acumulaban cientos de nodos
  /// efímeros: la lista crecía sin parar y el estado se reescribía entero cada
  /// pocos segundos. Se expulsan primero los que llevan más tiempo sin dar
  /// señales, y nunca un contacto de la libreta.
  final int maxPeers;

  void _trimPeers() {
    if (peers.length <= maxPeers) return;
    final removable =
        peers.values.where((p) => !p.isContact && p.id != identity.id).toList()
          ..sort((a, b) => a.lastSeen.compareTo(b.lastSeen));
    for (final peer in removable) {
      if (peers.length <= maxPeers) break;
      peers.remove(peer.id);
    }
  }

  bool _isFresh(MeshFrame frame) {
    final age = DateTime.now().millisecondsSinceEpoch - frame.timestamp;
    return age > -const Duration(minutes: 5).inMilliseconds &&
        age < const Duration(hours: 48).inMilliseconds;
  }

  static bool _sameKey(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
