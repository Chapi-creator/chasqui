import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'geo.dart';

/// Qué clase de mensaje viaja por el canal "Todos".
enum ChannelKind {
  /// Aviso normal para quien esté en la malla.
  message,

  /// Estado rápido: "estoy bien", "necesito ayuda", "estoy atrapado".
  status,

  /// Petición de auxilio: se guarda en cola y se reintenta.
  sos;

  String get code => switch (this) {
        ChannelKind.message => 'msg',
        ChannelKind.status => 'est',
        ChannelKind.sos => 'sos',
      };

  static ChannelKind fromCode(Object? code) => switch (code) {
        'sos' => ChannelKind.sos,
        'est' => ChannelKind.status,
        _ => ChannelKind.message,
      };
}

/// Estados rápidos que la UI ofrece con un toque.
enum QuickStatus {
  ok('Estoy bien'),
  help('Necesito ayuda'),
  trapped('Estoy atrapado');

  const QuickStatus(this.label);
  final String label;
}

/// Contenido de un mensaje del canal.
///
/// No va dirigido a nadie: lo lee cualquiera que esté en la malla. Por eso se
/// cifra con una clave de grupo derivada de una constante de la app (no es un
/// secreto: la seguridad aquí es que no viaje en claro por el aire) y cada
/// mensaje lleva el nombre del emisor en el propio contenido.
class ChannelMessage {
  ChannelMessage({
    required this.name,
    required this.text,
    this.kind = ChannelKind.message,
    this.battery,
    this.point,
  });

  final String name;
  final String text;
  final ChannelKind kind;

  /// Batería del emisor (0–100), si la conoce.
  final int? battery;

  /// Coordenadas adjuntas (el SOS las incluye si están disponibles).
  final GeoPoint? point;

  /// Tope de texto del canal. Es más corto que el de un chat privado porque
  /// estos avisos se repiten en toda la malla y conviene que quepan en pocos
  /// paquetes BLE.
  static const int maxTextBytes = 600;

  /// Se recorta al serializar: así ninguna ruta puede producir un contenido
  /// que el receptor descarte por tamaño.
  Map<String, dynamic> toJson() => {
        'v': 1,
        'n': clampUtf8Bytes(name, 48),
        't': clampUtf8Bytes(text, maxTextBytes),
        'k': kind.code,
        if (battery != null) 'b': battery,
        if (point != null) ...{
          'la': point!.lat,
          'lo': point!.lon,
          'ac': point!.accuracy,
        },
      };

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Lee un contenido recibido. Devuelve null si no es un canal válido.
  static ChannelMessage? decode(List<int> raw) {
    if (raw.isEmpty || raw.length > 2048) return null;
    try {
      final json = jsonDecode(utf8.decode(raw, allowMalformed: true));
      if (json is! Map) return null;
      final text = (json['t'] as String? ?? '').trim();
      final name = (json['n'] as String? ?? '').trim();
      if (text.isEmpty) return null;
      final battery = (json['b'] as num?)?.toInt();
      GeoPoint? point;
      if (json['la'] is num && json['lo'] is num) {
        final candidate = GeoPoint(
          lat: (json['la'] as num).toDouble(),
          lon: (json['lo'] as num).toDouble(),
          accuracy: (json['ac'] as num?)?.toDouble() ?? 0,
          at: DateTime.now(),
        );
        if (candidate.isValid) point = candidate;
      }
      return ChannelMessage(
        name: clampUtf8Bytes(name, 48),
        text: clampUtf8Bytes(text, maxTextBytes),
        kind: ChannelKind.fromCode(json['k']),
        battery: battery?.clamp(0, 100),
        point: point,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Aviso del canal que la capa de UI convierte en notificación del sistema.
class ChannelAlert {
  const ChannelAlert({
    required this.name,
    required this.text,
    required this.kind,
    required this.hops,
  });

  final String name;
  final String text;
  final ChannelKind kind;
  final int hops;
}

/// Cifrado del canal abierto.
///
/// Usa AES-256-GCM con una clave fija derivada de una cadena conocida. No hay
/// secreto que proteger: cualquiera con la app puede leer el canal (es su
/// propósito). Lo que sí evita es que el texto viaje legible para quien esté
/// capturando el aire y hace que una trama manipulada no descifre.
class ChannelCrypto {
  static final AesGcm _aes = AesGcm.with256bits();
  static final Sha256 _sha256 = Sha256();
  static Future<SecretKey>? _cachedKey;

  static const int nonceLength = 12;
  static const int macLength = 16;

  static Future<SecretKey> _key() {
    return _cachedKey ??= () async {
      final digest = await _sha256.hash(utf8.encode('sinred/v1/canal-todos'));
      return SecretKey(digest.bytes);
    }();
  }

  static Future<Uint8List> seal({
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: await _key(),
      nonce: randomBytes(nonceLength),
      aad: aad,
    );
    return box.concatenation();
  }

  /// Lanza [SecretBoxAuthenticationError] si la trama fue alterada.
  static Future<Uint8List> open({
    required List<int> sealed,
    required List<int> aad,
  }) async {
    if (sealed.length <= nonceLength + macLength) {
      throw const FormatException('Canal: payload demasiado corto');
    }
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: nonceLength,
      macLength: macLength,
    );
    final clear = await _aes.decrypt(box, secretKey: await _key(), aad: aad);
    return Uint8List.fromList(clear);
  }
}
