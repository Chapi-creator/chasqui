import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';
import 'identity.dart';

/// Código de invitación que lleva el QR para agregar a alguien como contacto.
///
/// Formato: `SINRED1:<id del nodo>:<clave pública>:<nombre en base64url>`
///
/// El id son los primeros 8 bytes de SHA-256 de la clave pública, así que al
/// leer el código se puede comprobar que la clave corresponde al id. Un QR
/// manipulado para hacerse pasar por otra persona se rechaza al agregarlo.
class ContactInvite {
  ContactInvite({
    required this.nodeId,
    required this.publicKey,
    required this.name,
  });

  /// Id del nodo en hex (16 caracteres).
  final String nodeId;

  /// Clave pública X25519 (32 bytes).
  final Uint8List publicKey;

  /// Nombre que la otra persona eligió para sí misma.
  final String name;

  static const String prefix = 'SINRED1';
  static const int publicKeyLength = 32;
  static const int nodeIdHexLength = 16;

  /// Mismo tope que el anuncio de presencia: un nombre más largo no cabría
  /// en una trama de malla.
  static const int maxNameBytes = 48;

  /// Texto que se muestra, se copia y se mete en el QR.
  String encode() =>
      '$prefix:$nodeId:${toHex(publicKey)}:${base64Url.encode(utf8.encode(name))}';

  @override
  String toString() => encode();

  /// Devuelve `null` si el texto no tiene el formato de una invitación.
  ///
  /// Es tolerante a espacios y saltos de línea (al copiar y pegar desde un
  /// chat se cuelan), pero estricto con la longitud y el contenido.
  static ContactInvite? decode(String raw) {
    final text = raw.replaceAll(RegExp(r'\s'), '');
    final parts = text.split(':');
    if (parts.length != 4) return null;
    if (parts[0].toUpperCase() != prefix) return null;

    final nodeId = parts[1].toLowerCase();
    if (!_isHex(nodeId) || nodeId.length != nodeIdHexLength) return null;

    final keyHex = parts[2].toLowerCase();
    if (!_isHex(keyHex) || keyHex.length != publicKeyLength * 2) return null;

    String decoded;
    try {
      decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts[3])));
    } catch (_) {
      return null;
    }
    final name = clampName(decoded);
    if (name.isEmpty) return null;

    return ContactInvite(
      nodeId: nodeId,
      publicKey: fromHex(keyHex),
      name: name,
    );
  }

  /// Comprueba que la clave pública del código corresponda a su id: es lo que
  /// impide que un QR falso suplante a un contacto conocido.
  Future<bool> verify() =>
      NodeIdentity.matchesNodeId(publicKey, fromHex(nodeId));

  /// Recorta el nombre a [maxNameBytes] en UTF-8 sin partir un carácter.
  static String clampName(String name) {
    final clean = name
        .replaceAll(RegExp('[\u0000-\u001f\u007f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in clean.runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (bytes + size > maxNameBytes) break;
      bytes += size;
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static bool _isHex(String value) => RegExp(r'^[0-9a-f]+$').hasMatch(value);
}

/// Alfabeto del código corto: 32 símbolos sin 0/O ni 1/I, que son los que se
/// confunden al dictar. La L se queda porque no hay un 1 con el que chocar.
const String contactCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Código corto de una persona, derivado de su id (estable para siempre).
///
/// Son 6 símbolos, pensados para dictarlos en voz alta o escribirlos a mano:
/// `ABC-DEF`.
String contactCodeOf(String nodeIdHex) {
  final clean = nodeIdHex.trim().toLowerCase();
  var value = 0;
  final bytes = clean.length ~/ 2;
  for (var i = 0; i < 4 && i < bytes; i++) {
    value = (value << 8) |
        int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  final buffer = StringBuffer();
  var rest = value;
  for (var i = 0; i < 6; i++) {
    buffer.write(contactCodeAlphabet[rest % contactCodeAlphabet.length]);
    rest ~/= contactCodeAlphabet.length;
  }
  return buffer.toString();
}

/// Presentación legible: `ABC-DEF`.
String formatContactCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)}-${code.substring(3)}' : code;

/// Acepta lo que la gente escribe de verdad: minúsculas, guiones, espacios.
String normalizeContactCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z2-9]'), '');

bool isValidContactCode(String code) =>
    code.length == 6 && RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code);

/// Resultado de agregar un contacto a partir de un código escaneado.
enum AddContactResult {
  /// Se agregó o se recuperó la ficha que ya existía en la malla.
  added,

  /// Ese id ya estaba en la libreta.
  already,

  /// El código es el de este mismo teléfono.
  ownCode,

  /// El texto no es un código de SinRed o la clave no cuadra con el id.
  invalid,

  /// (Código corto) Esa persona no está en la malla en este momento.
  notFound,

  /// (Código corto) Dos nodos distintos comparten ese código: no se adivina.
  ambiguous,
}
