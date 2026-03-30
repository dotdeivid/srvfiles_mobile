# services/crypto_service.dart

**File:** `lib/services/crypto_service.dart`

## Purpose

Provides ECDH P-256 + HKDF-SHA-256 + AES-256-GCM end-to-end encryption for WebSocket sessions. The implementation is wire-compatible with the Web Crypto API and Node.js `webcrypto`, so the mobile client can exchange files securely with browser peers and the desktop app.

## Exports / Public API

### `CryptoService` (static-only utility class)

| Method | Description |
|---|---|
| `static Future<SessionCipher?> clientKeyExchange({...})` | Client-side ECDH handshake. Generates an ephemeral P-256 key pair, calls `sendPublicKey` with the base64-encoded public key, then awaits `waitForPeerKey` for the server's public key. Returns a `SessionCipher` on success or `null` on timeout/error. |
| `static Future<({SessionCipher cipher, String serverPublicKey})> serverKeyExchange(String clientPublicKeyB64)` | Server-side ECDH handshake. Receives the client's base64 public key, generates an ephemeral key pair, derives the shared cipher, and returns both the cipher and the server's base64 public key to echo back. |

### `SessionCipher`

Wraps a derived AES-256-GCM `SecretKey` for a single WebSocket session.

| Method | Description |
|---|---|
| `Future<Map<String, String>> encryptJson(String plaintext)` | Encrypts a JSON string and returns `{'iv': <base64>, 'data': <base64>}` where `data` is `[cipherText][16-byte GCM tag]`. |
| `Future<String> decryptJson(String iv, String data)` | Decrypts an `{'iv', 'data'}` payload back to a JSON string. |
| `Future<Uint8List> encryptBinary(Uint8List payload)` | Encrypts binary data and returns `[12-byte nonce][cipherText][16-byte GCM tag]`. |
| `Future<Uint8List> decryptBinary(Uint8List data)` | Decrypts a binary frame in `[12-byte nonce][cipherText][16-byte GCM tag]` format. |

## Key behaviors

- **Public key wire format**: 65-byte uncompressed point — `0x04` prefix + 32-byte x + 32-byte y — encoded as base64. Keys that do not match this format throw `ArgumentError`.
- **HKDF info string**: `'srvfiles-ws-v1'` (must match the server-side constant for the derived key to be identical on both sides).
- **Key derivation**: `HKDF(HMAC-SHA-256, outputLength: 32)` with empty nonce/salt and the info string above.
- **JSON envelope**: `{'type': 'encrypted', 'iv': ..., 'data': ...}` (the relay wraps every encrypted JSON message in this envelope).
- **Binary frame**: `[12-byte nonce][cipherText][16-byte GCM tag]` — same layout as the Web Crypto API output, enabling cross-platform interoperability.
- Dependencies: `cryptography` package (for `Ecdh.p256`, `Hkdf`, `AesGcm.with256bits`).
