import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Tipos de trama que viajan por la malla.
enum FrameType {
  message(1),
  ack(2),
  presence(3),

  /// Coordenadas cifradas para un contacto concreto.
  location(4),

  /// Mensaje del canal abierto "Todos" (cifrado con clave de grupo).
  channel(5),

  /// Mensaje de un canal con nombre ("Refugio Norte"): clave derivada del
  /// nombre y de la contraseña opcional. Los teléfonos con una versión
  /// anterior no lo entienden y lo descartan sin reenviarlo.
  channelNamed(6),

  /// Trozo de una foto cifrada para un contacto concreto.
  photo(7);

  const FrameType(this.code);
  final int code;

  static FrameType fromCode(int code) => FrameType.values.firstWhere(
    (t) => t.code == code,
    orElse: () => throw FormatException('Tipo de trama desconocido: $code'),
  );
}

/// Trama de malla, formato binario compacto para que quepa en un solo paquete
/// BLE siempre que sea posible (cabecera de 47 bytes).
///
/// ```
/// 0        magic 0x53
/// 1        versión
/// 2        tipo
/// 3        ttl
/// 4        saltos
/// 5..20    id de trama (16)
/// 21..28   origen (8)
/// 29..36   destino (8)  (todo ceros = difusión)
/// 37..44   timestamp ms UTC (8)
/// 45..46   longitud del payload (2)
/// 47..     payload
/// ```
class MeshFrame {
  MeshFrame({
    required this.type,
    required this.id,
    required this.source,
    required this.destination,
    required this.timestamp,
    required this.payload,
    this.ttl = 3,
    this.hops = 0,
  });

  static const int magic = 0x53;
  static const int version = 1;
  static const int headerLength = 47;

  static final Uint8List broadcastId = Uint8List(8);

  final FrameType type;
  final Uint8List id;
  final Uint8List source;
  final Uint8List destination;
  final int timestamp;
  final Uint8List payload;
  final int ttl;
  final int hops;

  String get idHex => toHex(id);
  String get sourceHex => toHex(source);
  String get destinationHex => toHex(destination);
  bool get isBroadcast => destination.every((b) => b == 0);

  /// Clave de deduplicación: origen + id de trama.
  String get dedupKey => '$sourceHex:$idHex';

  /// Bytes que se autentican con el cifrado (no incluyen ttl/saltos, que
  /// cambian en cada reenvío).
  Uint8List authenticatedHeader() {
    final out = Uint8List(33);
    out[0] = type.code;
    out.setRange(1, 17, id);
    out.setRange(17, 25, source);
    out.setRange(25, 33, destination);
    return concatBytes([out, _uint64(timestamp)]);
  }

  MeshFrame forwarded() => MeshFrame(
    type: type,
    id: id,
    source: source,
    destination: destination,
    timestamp: timestamp,
    payload: payload,
    ttl: ttl - 1,
    hops: hops + 1,
  );

  /// Copia con otro TTL, sin tocar nada más.
  ///
  /// Se usa para acarrear una trama (mensajero): el que la lleva un rato en el
  /// bolsillo la reemite con saltos de nuevo, o el vecino la descartaría por
  /// venir agotada. TTL y saltos no van dentro de lo autenticado, así que ni el
  /// cifrado ni la comprobación de origen se enteran.
  MeshFrame refreshed(int ttl) => MeshFrame(
    type: type,
    id: id,
    source: source,
    destination: destination,
    timestamp: timestamp,
    payload: payload,
    ttl: ttl,
    hops: hops,
  );

  Uint8List encode() {
    final out = Uint8List(headerLength + payload.length);
    out[0] = magic;
    out[1] = version;
    out[2] = type.code;
    out[3] = ttl & 0xff;
    out[4] = hops & 0xff;
    out.setRange(5, 21, id);
    out.setRange(21, 29, source);
    out.setRange(29, 37, destination);
    writeUint64(out, 37, timestamp);
    writeUint16(out, 45, payload.length);
    out.setRange(headerLength, out.length, payload);
    return out;
  }

  static MeshFrame decode(List<int> raw) {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    if (bytes.length < headerLength) {
      throw const FormatException('Trama demasiado corta');
    }
    if (bytes[0] != magic) {
      throw const FormatException('Magic inválido');
    }
    if (bytes[1] != version) {
      throw FormatException('Versión no soportada: ${bytes[1]}');
    }
    final payloadLength = readUint16(bytes, 45);
    if (bytes.length != headerLength + payloadLength) {
      throw const FormatException('Payload inconsistente');
    }
    return MeshFrame(
      type: FrameType.fromCode(bytes[2]),
      ttl: bytes[3],
      hops: bytes[4],
      id: Uint8List.fromList(bytes.sublist(5, 21)),
      source: Uint8List.fromList(bytes.sublist(21, 29)),
      destination: Uint8List.fromList(bytes.sublist(29, 37)),
      timestamp: readUint64(bytes, 37),
      payload: Uint8List.fromList(bytes.sublist(headerLength)),
    );
  }

  /// Máximo de bytes que ocupa el nombre en el anuncio de presencia.
  static const int maxNameBytes = 48;

  /// Anuncio de presencia: clave pública X25519 (32) + nombre en UTF-8.
  static MeshFrame presence({
    required Uint8List source,
    required SimplePublicKey publicKey,
    required String name,
    int ttl = 2,
    int hops = 0,
  }) {
    final nameBytes = encodeName(name);
    final payload = Uint8List(1 + publicKey.bytes.length + nameBytes.length);
    payload[0] = nameBytes.length;
    payload.setRange(1, 1 + publicKey.bytes.length, publicKey.bytes);
    payload.setRange(1 + publicKey.bytes.length, payload.length, nameBytes);
    return MeshFrame(
      type: FrameType.presence,
      id: randomBytes(16),
      source: source,
      destination: broadcastId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
      ttl: ttl,
      hops: hops,
    );
  }

  /// Codifica el nombre en UTF-8 y lo recorta a [maxNameBytes] sin partir un
  /// carácter por la mitad (un emoji ocupa 4 bytes y cortarlo dejaría la
  /// presencia ilegible para todos los demás nodos).
  static Uint8List encodeName(String name) {
    final bytes = Uint8List.fromList(utf8.encode(name.trim()));
    if (bytes.length <= maxNameBytes) return bytes;
    var end = maxNameBytes;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return Uint8List.sublistView(bytes, 0, end);
  }

  static Uint8List _uint64(int value) {
    final out = Uint8List(8);
    writeUint64(out, 0, value);
    return out;
  }
}
