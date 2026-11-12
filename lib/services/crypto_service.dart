import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;

/// ECDH P-256 + HKDF-SHA-256 + AES-256-GCM session cipher.
///
/// Compatible with the Web Crypto API and the Go backend:
/// - P-256 public keys: 65 bytes (0x04 prefix + 32-byte x + 32-byte y)
/// - Shared secret: 32-byte x coordinate (Web Crypto `deriveBits(…, 256)`)
/// - AES-GCM ciphertext format: [cipherText][16-byte GCM tag]
/// - Binary frame format: [12-byte nonce][cipherText][16-byte GCM tag]
///
/// El ECDH se hace con pointycastle (Dart puro): `Ecdh.p256()` del paquete
/// `cryptography` lanza `UnimplementedError` sin plugin nativo, y eso dejaba
/// todas las sesiones sin cifrar. AES-GCM y HKDF siguen en `cryptography`
/// (nativos en el dispositivo cuando `FlutterCryptography.enable()` está activo).
///
/// Nota: el cifrado es salto a salto (cliente ↔ relay). El relay descifra y
/// vuelve a cifrar para el receptor, así que quien opera el relay puede ver el
/// contenido. El intercambio de claves no está autenticado.

const _hkdfInfo = 'srvfiles-ws-v1';

// Parámetros de la curva P-256 (secp256r1) para validar claves públicas.
final _p = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff', radix: 16);
final _a = _p - BigInt.from(3);
final _b = BigInt.parse(
    '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b', radix: 16);

class CryptoService {
  static final _domain = pc.ECDomainParameters('secp256r1');
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Client-side key exchange:
  /// Generates an ephemeral key pair, calls [sendPublicKey] with the base64 public key,
  /// then awaits [waitForPeerKey] to get the server's base64 public key,
  /// and returns a [SessionCipher] (or null on timeout/error).
  static Future<SessionCipher?> clientKeyExchange({
    required void Function(String pubKeyB64) sendPublicKey,
    required Future<String> Function() waitForPeerKey,
  }) async {
    final keyPair = _generateKeyPair();
    sendPublicKey(base64.encode(_encodePublicKey(keyPair.publicKey)));

    final peerPubKeyB64 = await waitForPeerKey();
    if (peerPubKeyB64.isEmpty) return null;

    return _deriveCipher(keyPair.privateKey, peerPubKeyB64);
  }

  /// Server-side key exchange:
  /// Receives the client's base64 public key, generates an ephemeral key pair,
  /// derives the shared [SessionCipher], and returns both the cipher and
  /// the server's base64 public key to send back to the client.
  static Future<({SessionCipher cipher, String serverPublicKey})> serverKeyExchange(
    String clientPublicKeyB64,
  ) async {
    final keyPair = _generateKeyPair();
    final cipher = await _deriveCipher(keyPair.privateKey, clientPublicKeyB64);
    return (
      cipher: cipher,
      serverPublicKey: base64.encode(_encodePublicKey(keyPair.publicKey)),
    );
  }

  // ─── Primitivas compartidas con el cifrado E2E (e2e_service.dart) ───

  /// Genera un par de claves P-256 efímero. La pública va en base64 (65 bytes).
  static ({pc.ECPrivateKey privateKey, String publicKeyB64}) generateKeyPairB64() {
    final pair = _generateKeyPair();
    return (privateKey: pair.privateKey, publicKeyB64: base64.encode(_encodePublicKey(pair.publicKey)));
  }

  /// Clave privada P-256 a partir de su escalar (solo para vectores de prueba).
  static pc.ECPrivateKey privateKeyFromHex(String hex) =>
      pc.ECPrivateKey(BigInt.parse(hex, radix: 16), _domain);

  /// Clave pública base64 de una privada (solo para vectores de prueba).
  static String publicKeyB64Of(pc.ECPrivateKey key) =>
      base64.encode((_domain.G * key.d)!.getEncoded(false));

  /// Secreto ECDH (coordenada x, 32 bytes) con la clave pública del otro lado.
  /// Lanza ArgumentError si la clave no es un punto válido de P-256.
  static Uint8List sharedSecret(pc.ECPrivateKey privateKey, String peerPublicKeyB64) {
    final peerBytes = base64.decode(peerPublicKeyB64);
    if (peerBytes.length != 65 || peerBytes[0] != 0x04) {
      throw ArgumentError('Expected 65-byte uncompressed P-256 public key');
    }
    final x = _toBigInt(peerBytes.sublist(1, 33));
    final y = _toBigInt(peerBytes.sublist(33, 65));
    if (!_isOnCurve(x, y)) throw ArgumentError('Peer public key is not a valid P-256 point');
    final peerKey = pc.ECPublicKey(_domain.curve.decodePoint(peerBytes)!, _domain);
    final agreement = pc.ECDHBasicAgreement()..init(privateKey);
    return _toBytes(agreement.calculateAgreement(peerKey), 32);
  }

  // ─── Internos ──────────────────────────────────────────────────────

  static ({pc.ECPrivateKey privateKey, pc.ECPublicKey publicKey}) _generateKeyPair() {
    final generator = pc.ECKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.ECKeyGeneratorParameters(_domain),
        _secureRandom(),
      ));
    final pair = generator.generateKeyPair();
    return (
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
    );
  }

  static pc.SecureRandom _secureRandom() {
    final rng = Random.secure();
    final seed = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    return pc.FortunaRandom()..seed(pc.KeyParameter(seed));
  }

  static Uint8List _encodePublicKey(pc.ECPublicKey key) =>
      key.Q!.getEncoded(false); // 0x04 || x || y

  /// Derives a [SessionCipher] from a local private key and the peer's base64 public key.
  /// The peer's public key must be 65 bytes (0x04 + x + y) and lie on P-256.
  static Future<SessionCipher> _deriveCipher(
    pc.ECPrivateKey privateKey,
    String peerPublicKeyB64,
  ) async {
    final shared = sharedSecret(privateKey, peerPublicKeyB64);

    final derivedKey = await _hkdf.deriveKey(
      secretKey: SecretKey(shared),
      nonce: const [],
      info: utf8.encode(_hkdfInfo),
    );

    final keyBytes = await derivedKey.extractBytes();
    return SessionCipher(SecretKey(keyBytes));
  }

  static bool _isOnCurve(BigInt x, BigInt y) {
    if (x >= _p || y >= _p || x.isNegative || y.isNegative) return false;
    final left = (y * y) % _p;
    final right = (x * x * x + _a * x + _b) % _p;
    return left == right;
  }

  static BigInt _toBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _toBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }
}

/// AES-256-GCM cipher for a single WebSocket session.
class SessionCipher {
  final SecretKey _key;
  static final _aesGcm = AesGcm.with256bits();

  static const _nonceLength = 12;
  static const _tagLength = 16;

  SessionCipher(this._key);

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
    final combined = (BytesBuilder(copy: false)
          ..add(secretBox.cipherText)
          ..add(secretBox.mac.bytes))
        .takeBytes();
    return {
      'iv': base64.encode(nonce),
      'data': base64.encode(combined),
    };
  }

  /// Decrypts an `{'iv': ..., 'data': ...}` payload and returns the plaintext JSON.
  Future<String> decryptJson(String iv, String data) async {
    final nonce = base64.decode(iv);
    final combined = base64.decode(data);
    if (combined.length < _tagLength) throw ArgumentError('Ciphertext too short');
    final split = combined.length - _tagLength;
    final secretBox = SecretBox(
      Uint8List.sublistView(combined, 0, split),
      nonce: nonce,
      mac: Mac(Uint8List.sublistView(combined, split)),
    );
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
    return (BytesBuilder(copy: false)
          ..add(nonce)
          ..add(secretBox.cipherText)
          ..add(secretBox.mac.bytes))
        .takeBytes();
  }

  /// Decrypts a binary frame with format `[12-byte nonce][cipherText][16-byte GCM tag]`.
  Future<Uint8List> decryptBinary(Uint8List data) async {
    if (data.length < _nonceLength + _tagLength) {
      throw ArgumentError('Encrypted frame too short');
    }
    final tagStart = data.length - _tagLength;
    final secretBox = SecretBox(
      Uint8List.sublistView(data, _nonceLength, tagStart),
      nonce: Uint8List.sublistView(data, 0, _nonceLength),
      mac: Mac(Uint8List.sublistView(data, tagStart)),
    );
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: _key);
    return plainBytes is Uint8List ? plainBytes : Uint8List.fromList(plainBytes);
  }
}
