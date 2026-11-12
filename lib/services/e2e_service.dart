import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;
import 'crypto_service.dart';

/// Cifrado de extremo a extremo de una transferencia (ver docs/protocol.md
/// en srvfiles_web). Mismo algoritmo que la web (lib/e2e.ts):
///
///   okm = HKDF-SHA-256(ECDH, salt = transferId,
///                      info = "srvfiles-e2e-v1" ‖ pubEmisor ‖ pubReceptor, 36 bytes)
///   key = okm[0..32] → AES-256-GCM
///   SAS = uint32(okm[32..36]) mod 1 000 000 → código de 6 dígitos que ambos comparan
///
/// Chunk i: nonce = 0x00000000 ‖ uint64(i), AAD = transferId. El marcador
/// final usa el índice N (cantidad de chunks) y AAD = transferId + "|end".
/// Un chunk reordenado, repetido, perdido o alterado no se descifra.
class E2EKeyPair {
  final pc.ECPrivateKey privateKey;

  /// base64 de la clave pública sin comprimir (65 bytes).
  final String publicKey;

  E2EKeyPair._(this.privateKey, this.publicKey);

  factory E2EKeyPair.generate() {
    final pair = CryptoService.generateKeyPairB64();
    return E2EKeyPair._(pair.privateKey, pair.publicKeyB64);
  }

  /// Solo para vectores de prueba.
  factory E2EKeyPair.fromPrivateHex(String hex) {
    final key = CryptoService.privateKeyFromHex(hex);
    return E2EKeyPair._(key, CryptoService.publicKeyB64Of(key));
  }
}

class E2ESession {
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 36);
  static final _aes = AesGcm.with256bits();
  static final _info = utf8.encode('srvfiles-e2e-v1');

  final SecretKey _key;
  final List<int> _aad;
  final List<int> _aadEnd;

  /// Código de verificación de 6 dígitos.
  final String sas;

  E2ESession._(this._key, String transferId, this.sas)
      : _aad = utf8.encode(transferId),
        _aadEnd = utf8.encode('$transferId|end');

  /// Deriva la sesión con la clave privada propia y la pública del otro lado.
  /// [senderPublicKey] y [receiverPublicKey] en base64 (una de las dos es la propia).
  static Future<E2ESession> derive({
    required pc.ECPrivateKey ownPrivateKey,
    required String peerPublicKey,
    required String senderPublicKey,
    required String receiverPublicKey,
    required String transferId,
  }) async {
    final shared = CryptoService.sharedSecret(ownPrivateKey, peerPublicKey);
    final info = <int>[..._info, ...base64.decode(senderPublicKey), ...base64.decode(receiverPublicKey)];
    final okmKey = await _hkdf.deriveKey(
      secretKey: SecretKey(shared),
      nonce: utf8.encode(transferId),
      info: info,
    );
    final okm = await okmKey.extractBytes();
    final sasNum = ByteData.sublistView(Uint8List.fromList(okm), 32, 36).getUint32(0) % 1000000;
    return E2ESession._(
      SecretKey(okm.sublist(0, 32)),
      transferId,
      sasNum.toString().padLeft(6, '0'),
    );
  }

  /// Formato para mostrar: "123 456".
  static String formatSas(String sas) => '${sas.substring(0, 3)} ${sas.substring(3)}';

  static List<int> _nonce(int index) {
    final n = Uint8List(12);
    ByteData.sublistView(n).setUint64(4, index);
    return n;
  }

  Future<Uint8List> encryptChunk(int index, List<int> data) async {
    final box = await _aes.encrypt(data, secretKey: _key, nonce: _nonce(index), aad: _aad);
    return (BytesBuilder(copy: false)..add(box.cipherText)..add(box.mac.bytes)).takeBytes();
  }

  /// Lanza SecretBoxAuthenticationError si el chunk fue alterado o no
  /// corresponde a ese índice.
  Future<Uint8List> decryptChunk(int index, Uint8List data) async {
    if (data.length < 16) throw ArgumentError('Chunk too short');
    final split = data.length - 16;
    final plain = await _aes.decrypt(
      SecretBox(Uint8List.sublistView(data, 0, split),
          nonce: _nonce(index), mac: Mac(Uint8List.sublistView(data, split))),
      secretKey: _key,
      aad: _aad,
    );
    return plain is Uint8List ? plain : Uint8List.fromList(plain);
  }

  /// Marcador final cifrado: cantidad de chunks, tamaño y nombre.
  Future<String> encryptFinal({required int chunks, required int size, required String name}) async {
    final plain = utf8.encode(jsonEncode({'chunks': chunks, 'size': size, 'name': name}));
    final box = await _aes.encrypt(plain, secretKey: _key, nonce: _nonce(chunks), aad: _aadEnd);
    return base64.encode([...box.cipherText, ...box.mac.bytes]);
  }

  Future<({int chunks, int size, String name})> decryptFinal(int chunks, String b64) async {
    final data = base64.decode(b64);
    if (data.length < 16) throw ArgumentError('Final marker too short');
    final split = data.length - 16;
    final plain = await _aes.decrypt(
      SecretBox(data.sublist(0, split), nonce: _nonce(chunks), mac: Mac(data.sublist(split))),
      secretKey: _key,
      aad: _aadEnd,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return (
      chunks: (json['chunks'] as num).toInt(),
      size: (json['size'] as num).toInt(),
      name: json['name'] as String,
    );
  }
}
