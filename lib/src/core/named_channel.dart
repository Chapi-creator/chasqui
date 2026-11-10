import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Un canal con nombre: "Refugio Norte", "Cuadrilla 3", "Edificio B".
///
/// No hay servidor que registre canales. El nombre **es** el canal: el id y la
/// clave se derivan de él con SHA-256, así que dos teléfonos que escriban el
/// mismo nombre (y la misma clave, si tiene) hablan entre ellos sin haberse
/// conocido nunca. Es lo mismo que hace un chat de sala por radio: quien sabe
/// el nombre está adentro.
class NamedChannel {
  NamedChannel({
    required this.id,
    required this.name,
    required this.passphrase,
    this.createdByMe = false,
    DateTime? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now();

  /// Id corto en hex (16 caracteres) derivado del nombre y la clave.
  final String id;

  /// Nombre tal como lo escribió quien lo creó o entró.
  final String name;

  /// Clave opcional. Sin clave el canal es abierto pero separado de "Todos";
  /// con clave, solo entra quien la sepa.
  final String? passphrase;

  /// Quién lo creó desde este teléfono (solo cambia el texto de la lista).
  final bool createdByMe;

  final DateTime joinedAt;

  /// Id de conversación en el almacén local: cada canal tiene su historial.
  String get peerId => 'canal:$id';

  bool get isPrivate => passphrase != null && passphrase!.isNotEmpty;

  /// Id interno (8 bytes) tal como viaja en la trama.
  Uint8List get idBytes => Uint8List.fromList(fromHex(id));

  /// Nombre normalizado: minúsculas, sin espacios de más.
  ///
  /// "Refugio  Norte" y "refugio norte" tienen que ser el mismo canal: la
  /// gente escribe con mayúsculas y espacios distintos y no hay nadie que
  /// corrija.
  static String normalize(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Nombre listo para mostrar: se respeta lo que escribió el usuario.
  static String display(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool isValidName(String raw) {
    final clean = display(raw);
    if (clean.length < 2 || clean.length > 32) return false;
    // El nombre viaja dentro de un JSON corto: se acepta cualquier cosa
    // imprimible, pero no saltos de línea ni caracteres de control.
    return !clean.contains(RegExp(r'[\u0000-\u001f]'));
  }

  static bool isValidPassphrase(String? raw) {
    if (raw == null || raw.isEmpty) return true;
    return raw.length <= 64 && !raw.contains(RegExp(r'[\u0000-\u001f]'));
  }

  /// Semilla común de id y clave. Lleva versión y prefijo para no chocar con
  /// otros hashes de la app (el canal "Todos" incluido).
  static List<int> _seed(String rawName, String? rawPass) {
    final name = normalize(rawName);
    final pass = rawPass?.trim() ?? '';
    return utf8.encode('chasqui/v1/canal:$name\u0000$pass');
  }

  /// Id del canal a partir del nombre y la clave.
  ///
  /// La clave entra en el id: si alguien crea "Refugio Norte" con clave y otro
  /// crea el mismo nombre sin clave, son dos canales distintos y no se mezclan
  /// mensajes que uno no puede leer.
  static Future<String> idFor(String name, String? passphrase) async {
    final digest = await Sha256().hash(_seed(name, passphrase));
    return toHex(digest.bytes.sublist(0, 8));
  }

  /// Clave AES-256 del canal. Con clave elegida, es un secreto compartido por
  /// quienes la saben; sin clave, el canal es público pero el aire no ve el
  /// texto en claro.
  static Future<SecretKey> keyFor(String name, String? passphrase) async {
    final digest = await Sha256().hash(_seed(name, passphrase));
    return SecretKey(digest.bytes);
  }

  Future<SecretKey> key() => keyFor(name, passphrase);

  /// Arma el canal sin id (se calcula en [create]).
  static Future<NamedChannel> create({
    required String name,
    String? passphrase,
    bool createdByMe = false,
    DateTime? joinedAt,
  }) async {
    final cleanName = display(name);
    final cleanPass = (passphrase ?? '').trim();
    final id = await idFor(cleanName, cleanPass.isEmpty ? null : cleanPass);
    return NamedChannel(
      id: id,
      name: cleanName,
      passphrase: cleanPass.isEmpty ? null : cleanPass,
      createdByMe: createdByMe,
      joinedAt: joinedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (passphrase != null) 'pass': passphrase,
    if (createdByMe) 'mine': true,
    'since': joinedAt.millisecondsSinceEpoch,
  };

  static NamedChannel? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String) return null;
    if (id.length != 16 || !RegExp(r'^[0-9a-f]+$').hasMatch(id)) return null;
    final pass = raw['pass'];
    return NamedChannel(
      id: id,
      name: display(name),
      passphrase: pass is String && pass.isNotEmpty ? pass : null,
      createdByMe: raw['mine'] == true,
      joinedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['since'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
