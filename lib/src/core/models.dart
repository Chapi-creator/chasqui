import 'dart:typed_data';

import 'bytes.dart';
import 'geo.dart';

enum MessageStatus { queued, sent, delivered, failed }

/// Qué contiene una entrada del historial.
enum MessageKind {
  /// Texto normal.
  text,

  /// Coordenadas compartidas a propósito desde el chat.
  location,

  /// Interpretación local de unas coordenadas (el "asistente" sin IA).
  assistant,

  /// Estado rápido del canal ("estoy bien", "necesito ayuda").
  status,

  /// Petición de auxilio del canal.
  sos,
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.peerId,
    required this.outgoing,
    required this.text,
    required this.timestamp,
    this.status = MessageStatus.queued,
    this.hops = 0,
    this.kind = MessageKind.text,
    this.location,
    this.senderName,
  });

  final String id;
  final String peerId;
  final bool outgoing;
  final String text;
  final DateTime timestamp;
  MessageStatus status;

  /// Saltos de malla que recorrió (0 = enlace directo).
  int hops;

  final MessageKind kind;

  /// Coordenadas, solo en mensajes de tipo [MessageKind.location].
  final GeoPoint? location;

  /// Quién lo mandó, cuando el mensaje viene del canal abierto.
  ///
  /// En un chat privado el nombre ya está en el contacto; en el canal hay
  /// muchos emisores en la misma conversación, así que cada burbuja lo lleva.
  final String? senderName;

  ChatMessage copyWith({MessageStatus? status, int? hops}) => ChatMessage(
        id: id,
        peerId: peerId,
        outgoing: outgoing,
        text: text,
        timestamp: timestamp,
        status: status ?? this.status,
        hops: hops ?? this.hops,
        kind: kind,
        location: location,
        senderName: senderName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'outgoing': outgoing,
        'text': text,
        'ts': timestamp.millisecondsSinceEpoch,
        'status': status.name,
        'hops': hops,
        'kind': kind.name,
        if (location != null) 'geo': location!.toMap(),
        if (senderName != null) 'from': senderName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        peerId: json['peerId'] as String,
        outgoing: json['outgoing'] as bool,
        text: json['text'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt()),
        status: MessageStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => MessageStatus.queued,
        ),
        hops: (json['hops'] as num?)?.toInt() ?? 0,
        kind: MessageKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => MessageKind.text,
        ),
        location: GeoPoint.fromMap(json['geo']),
        senderName: json['from'] as String?,
      );
}

/// Nodo conocido de la malla (contacto o simple repetidor).
class PeerRecord {
  PeerRecord({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.lastSeen,
    this.hops = 0,
    this.rssi,
    this.directLink = false,
    this.batteryFriendly = true,
    this.isContact = false,
    this.contactSince,
  });

  final String id;
  String name;
  Uint8List publicKey;
  DateTime lastSeen;
  int hops;
  int? rssi;

  /// True si hay un enlace BLE directo con este nodo.
  bool directLink;

  /// El nodo se anuncia como de bajo consumo (no reenvía todo).
  bool batteryFriendly;

  /// Está en la libreta de contactos (agregado por QR o código pegado).
  bool isContact;

  /// Cuándo se agregó a la libreta.
  DateTime? contactSince;

  /// Última posición que compartió este nodo.
  ///
  /// No se persiste a propósito: una ubicación de ayer mostrada como "ahora"
  /// sería una mentira silenciosa. Al reabrir la app hay que volver a recibirla.
  GeoPoint? location;

  String get shortCode => shortId(id);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': toHex(publicKey),
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'hops': hops,
        'rssi': rssi,
        'batteryFriendly': batteryFriendly,
        'contact': isContact,
        'since': contactSince?.millisecondsSinceEpoch,
      };

  factory PeerRecord.fromJson(Map<String, dynamic> json) => PeerRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        publicKey: fromHex(json['key'] as String),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (json['lastSeen'] as num).toInt()),
        hops: (json['hops'] as num?)?.toInt() ?? 0,
        rssi: (json['rssi'] as num?)?.toInt(),
        batteryFriendly: json['batteryFriendly'] as bool? ?? true,
        isContact: json['contact'] as bool? ?? false,
        contactSince: json['since'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['since'] as num).toInt(),
              ),
      );
}
