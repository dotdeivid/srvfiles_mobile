# services/transfer_service.dart

**File:** `lib/services/transfer_service.dart`

## Purpose

WebSocket client for the SrvFiles P2P transfer protocol. Manages the connection to a relay server, handles JSON signaling messages, performs ECDH key exchange for end-to-end encryption, and streams binary file chunks. Mirrors `transfer.api.ts` from the frontend web.

## Exports / Public API

### Constants

| Constant | Value | Description |
|---|---|---|
| `chunkSize` | `256 * 1024` (256 KB) | Binary chunk size — matches the web frontend. |
| `transferIdLength` | `36` | Length of the UUID header prepended to binary frames. |

### `TransferService`

**Callbacks (all nullable, set by `TransferController`):**

| Callback | Signature | Description |
|---|---|---|
| `onAuthOk` | `void Function()` | Fired after `auth_ok` + key exchange. |
| `onWelcome` | `void Function(String clientId)` | Fired on `welcome` with this client's assigned ID. |
| `onClientsUpdate` | `void Function(List<TransferClient>)` | Fired on `clients` broadcast. |
| `onSendRequest` | `void Function(IncomingTransferRequest)` | Incoming transfer request from a peer. |
| `onSendAccept` | `void Function(String transferId)` | Peer accepted our transfer request. |
| `onSendReject` | `void Function(String transferId, String? reason)` | Peer rejected. |
| `onSendCancel` | `void Function(String transferId)` | Transfer was cancelled. |
| `onSendComplete` | `void Function(String transferId)` | Sender signalled all chunks sent. |
| `onBinaryChunk` | `void Function(String transferId, Uint8List data)` | A decrypted binary chunk arrived. |
| `onDisconnected` | `void Function()` | WebSocket closed unexpectedly. |
| `onFilesChanged` | `void Function()` | Relay broadcast `files-changed`. |
| `onAuthRequired` | `void Function()` | WebSocket closed with code `4401` (token invalid). |

**Getters:**

| Getter | Description |
|---|---|
| `String? clientId` | This client's relay-assigned ID (available after `welcome`). |
| `bool isConnected` | `true` if channel is open and not disposed. |
| `bool hasToken` | `true` if a session token has been set via `setToken`. |

**Methods:**

| Method | Description |
|---|---|
| `void setToken(String token)` | Stores a session token for authenticated connections. |
| `void clearToken()` | Removes the session token. |
| `void connect(ApiConfig config)` | Connects to `config.wsUrl`. Cancels any existing connection first. If a token is set, sends `{'type': 'auth', 'token': ...}` immediately after opening. |
| `void register(String appName)` | Sends `hello` with `deviceType: 'mobile'`. |
| `void setReceiving(bool receiving)` | Sends `set-receiving`. |
| `void sendRequest({to, fileName, fileSize, mimeType, transferId})` | Sends `send-request`. |
| `void accept(String transferId)` | Sends `send-accept`. |
| `void reject(String transferId)` | Sends `send-reject`. |
| `void cancel(String transferId)` | Sends `send-cancel`. |
| `void rename(String newName)` | Sends `rename`. |
| `Future<void> sendFile({transferId, fileBytes, onProgress?})` | Sends the file as 256 KB binary chunks. Each frame is `[36-byte transferId][chunk data]`. Yields to the event loop after each chunk with `Future.delayed(Duration.zero)`. Sends `send-complete` after all chunks. |
| `void dispose()` | Closes the WebSocket and cancels the subscription. |

## Key behaviors — ECDH key exchange

On receiving `auth_ok`, the service immediately performs a client-side key exchange:
1. Calls `CryptoService.clientKeyExchange`, sending `{'type': 'key-exchange', 'publicKey': <base64>}`.
2. Waits up to 5 seconds for the server's `key-exchange` reply via a `Completer`.
3. On success, `_cipher` is set to the derived `SessionCipher`.
4. After key exchange completes, `onAuthOk` is called.

## Key behaviors — encrypted send queue

JSON messages are sent through `_sendJson`, which maintains a `Future<void> _sendQueue` chain to preserve message ordering when async encryption is involved:
- Without cipher: sends directly to the channel sink.
- With cipher: encrypts asynchronously in the queue, wraps in `{'type': 'encrypted', 'iv': ..., 'data': ...}`.

Binary chunks are encrypted with `cipher.encryptBinary` (inline await, no queue — binary order is maintained by the sequential `while` loop).

## Key behaviors — binary frame format

```
[36 bytes: transferId padded with spaces][N bytes: chunk data]
```

The receiver reads the first 36 bytes to route the chunk to the correct buffer, then passes the remainder to `onBinaryChunk`.

- Dependencies: `web_socket_channel`, `CryptoService`, `ApiConfig`, `TransferClient`, `IncomingTransferRequest`, `AppLogger`.
