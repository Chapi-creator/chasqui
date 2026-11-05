import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'identity.dart';

/// Cifrado de extremo a extremo de la malla.
///
/// ECDH estático (X25519) entre emisor y receptor + HKDF-SHA256 + AES-256-GCM.
/// El emisor queda autenticado implícitamente porque la clave derivada solo la
/// pueden calcular él y el receptor. No hay forward secrecy: para el MVP se
/// prioriza un sobre pequeño (28 bytes) y cero negociación por mensaje.
class MeshCrypto {
  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final AesGcm _aes = AesGcm.with256bits();
  static final Sha256 _sha256 = Sha256();

  static const int nonceLength = 12;
  static const int macLength = 16;

  static Future<SecretKey> _deriveKey({
    required NodeIdentity me,
    required SimplePublicKey peer,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: SimpleKeyPairData(
        me.privateKeyBytes,
        publicKey: me.publicKey,
        type: KeyPairType.x25519,
      ),
      remotePublicKey: peer,
    );
    final a = me.publicKey.bytes;
    final b = peer.bytes;
    final ordered = compareBytes(a, b) <= 0
        ? concatBytes([a, b])
        : concatBytes([b, a]);
    final salt = await _sha256.hash(ordered);
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: salt.bytes,
      info: utf8.encode('sinred/v1/mesh-message'),
    );
  }

  /// Cifra y autentica [plaintext] del emisor [me] hacia [peer].
  static Future<Uint8List> seal({
    required NodeIdentity me,
    required SimplePublicKey peer,
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    final key = await _deriveKey(me: me, peer: peer);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      nonce: randomBytes(nonceLength),
      aad: aad,
    );
    return box.concatenation();
  }

  /// Descifra y verifica. Lanza [SecretBoxAuthenticationError] si la trama fue
  /// manipulada o no viene de quien dice.
  static Future<Uint8List> open({
    required NodeIdentity me,
    required SimplePublicKey peer,
    required List<int> sealed,
    required List<int> aad,
  }) async {
    final key = await _deriveKey(me: me, peer: peer);
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: nonceLength,
      macLength: macLength,
    );
    final clear = await _aes.decrypt(box, secretKey: key, aad: aad);
    return Uint8List.fromList(clear);
  }
}
