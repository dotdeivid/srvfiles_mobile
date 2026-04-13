import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// ECDH P-256 + HKDF-SHA-256 + AES-256-GCM session cipher.
///
/// Compatible with the Web Crypto API and Node.js webcrypto:
/// - P-256 public keys: 65 bytes (0x04 prefix + 32-byte x + 32-byte y)
/// - AES-GCM ciphertext format: [cipherText][16-byte GCM tag]
/// - Binary frame format: [12-byte nonce][cipherText][16-byte GCM tag]

const _hkdfInfo = 'srvfiles-ws-v1';

class CryptoService {
  static final _ecdh = Ecdh.p256(length: 32);
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Client-side key exchange:
  /// Generates an ephemeral key pair, calls [sendPublicKey] with the base64 public key,
  /// then awaits [waitForPeerKey] to get the server's base64 public key,
  /// and returns a [SessionCipher] (or null on timeout/error).
  static Future<SessionCipher?> clientKeyExchange({
    required void Function(String pubKeyB64) sendPublicKey,
    required Future<String> Function() waitForPeerKey,
  }) async {
    final keyPair = await _ecdh.newKeyPair();
    final pubKey = await keyPair.extractPublicKey();
    final pubKeyBytes = Uint8List.fromList([0x04, ...pubKey.x, ...pubKey.y]);
    sendPublicKey(base64.encode(pubKeyBytes));

    final peerPubKeyB64 = await waitForPeerKey();
    if (peerPubKeyB64.isEmpty) return null;

    return _deriveCipher(keyPair, peerPubKeyB64);
  }

  /// Server-side key exchange:
  /// Receives the client's base64 public key, generates an ephemeral key pair,
  /// derives the shared [SessionCipher], and returns both the cipher and
  /// the server's base64 public key to send back to the client.
  static Future<({SessionCipher cipher, String serverPublicKey})> serverKeyExchange(
    String clientPublicKeyB64,
  ) async {
    final serverKeyPair = await _ecdh.newKeyPair();
    final serverPubKey = await serverKeyPair.extractPublicKey();
    final serverPubKeyBytes = Uint8List.fromList([0x04, ...serverPubKey.x, ...serverPubKey.y]);
    final cipher = await _deriveCipher(serverKeyPair, clientPublicKeyB64);
    return (cipher: cipher, serverPublicKey: base64.encode(serverPubKeyBytes));
  }

  /// Derives a [SessionCipher] from a local key pair and the peer's base64 public key.
  /// The peer's public key must be 65 bytes (0x04 + x + y) encoded as base64.
  static Future<SessionCipher> _deriveCipher(EcKeyPair keyPair, String peerPublicKeyB64) async {
    final peerBytes = base64.decode(peerPublicKeyB64);
    if (peerBytes.length != 65 || peerBytes[0] != 0x04) {
      throw ArgumentError('Expected 65-byte uncompressed P-256 public key (0x04 prefix), got ${peerBytes.length} bytes');
    }
    final x = peerBytes.sublist(1, 33);
    final y = peerBytes.sublist(33, 65);
    final peerPublicKey = EcPublicKey(x: x, y: y, type: KeyPairType.p256);

    final sharedSecret = await _ecdh.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: peerPublicKey,
    );

    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: const [],
      info: utf8.encode(_hkdfInfo),
    );

    final keyBytes = await derivedKey.extractBytes();
    return SessionCipher(SecretKey(keyBytes), keyBytes);
  }
}

/// AES-256-GCM cipher for a single WebSocket session.
class SessionCipher {
  final SecretKey _key;
  /// Raw key bytes — exposed for isolate-based encryption via compute().
  final List<int> keyBytes;
  static final _aesGcm = AesGcm.with256bits();

  SessionCipher(this._key, this.keyBytes);

  /// Encrypts [plaintext] (JSON string) and returns `{'iv': ..., 'data': ...}`.
  /// The `data` field is base64([cipherText][16-byte GCM tag]).
  Future<Map<String, String>> encryptJson(String plaintext) async {
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: _key,
      nonce: nonce,
    );
    // Combine cipherText + GCM tag — matches Web Crypto API output format
    final combined = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return {
      'iv': base64.encode(nonce),
      'data': base64.encode(combined),
    };
  }

  /// Decrypts an `{'iv': ..., 'data': ...}` payload and returns the plaintext JSON.
  Future<String> decryptJson(String iv, String data) async {
    final nonce = base64.decode(iv);
    final combined = base64.decode(data);
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: _key);
    return utf8.decode(plainBytes);
  }

  /// Encrypts a binary [payload] and returns `[12-byte nonce][cipherText][16-byte GCM tag]`.
  Future<Uint8List> encryptBinary(Uint8List payload) async {
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      payload,
      secretKey: _key,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// Decrypts a binary frame with format `[12-byte nonce][cipherText][16-byte GCM tag]`.
  Future<Uint8List> decryptBinary(Uint8List data) async {
    final nonce = data.sublist(0, 12);
    final combined = data.sublist(12);
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: _key);
    return Uint8List.fromList(plainBytes);
  }
}
