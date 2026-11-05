import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Identidad local del nodo: par de claves X25519 + id corto derivado.
///
/// El id del nodo son los primeros 8 bytes de SHA-256 de la clave pública.
/// Con eso cualquier nodo puede verificar que quien anuncia una clave pública
/// no está suplantando a otro (TOFU con verificación de prefijo).
class NodeIdentity {
  NodeIdentity._(this._keyPair, this.nodeId);

  final SimpleKeyPairData _keyPair;
  final Uint8List nodeId;

  static final X25519 _x25519 = X25519();
  static final Sha256 _sha256 = Sha256();

  SimplePublicKey get publicKey => _keyPair.publicKey;

  Uint8List get privateKeyBytes => Uint8List.fromList(_keyPair.bytes);

  Uint8List get publicKeyBytes => Uint8List.fromList(publicKey.bytes);

  String get id => toHex(nodeId);

  static Future<NodeIdentity> generate() async {
    final keyPair = await _x25519.newKeyPair();
    final data = await keyPair.extract();
    return _fromKeyPair(data);
  }

  static Future<NodeIdentity> fromPrivateKey(List<int> privateKeyBytes) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
    final data = await keyPair.extract();
    return _fromKeyPair(data);
  }

  static Future<NodeIdentity> _fromKeyPair(SimpleKeyPairData data) async {
    final digest = await _sha256.hash(data.publicKey.bytes);
    final nodeId = Uint8List.fromList(digest.bytes.sublist(0, 8));
    return NodeIdentity._(data, nodeId);
  }

  /// Comprueba que una clave pública anunciada corresponda al id que la firma.
  static Future<bool> matchesNodeId(List<int> publicKey, List<int> nodeId) async {
    final digest = await _sha256.hash(publicKey);
    final expected = digest.bytes.sublist(0, 8);
    if (expected.length != nodeId.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] != nodeId[i]) return false;
    }
    return true;
  }
}
