# services/relay/relay_ws_handler.dart

**File:** `lib/services/relay/relay_ws_handler.dart`

## Purpose

Handles WebSocket upgrade, client lifecycle management, JSON signaling (hello/welcome, send-request/accept/reject/cancel/complete, rename), ECDH key exchange, and binary chunk relaying for the embedded relay. Decrypts incoming frames from the sender and re-encrypts for the receiver if the respective sessions have ciphers.

## Exports / Public API

### `RelayWsHandler`

**Constructor parameters (all required):**

| Parameter | Description |
|---|---|
| `Map<String, ConnectedClient> clients` | Shared map of connected clients (also written to by this handler). |
| `Map<String, TransferSession> transfers` | Shared map of active transfers. |
| `Map<String, bool> sessions` | Session tokens from `RelayAuth.sessions` — checked on WS auth. |
| `bool Function() isServerMode` | Lambda returning current server mode state. |
| `String Function() generateUuid` | Lambda for generating client IDs. |
| `void Function() broadcastClients` | Called whenever the client list changes. |
| `void Function() broadcastFilesChanged` | Called when files change (from server mode upload/delete — not currently triggered via WS, but wired for future use). |

**Methods:**

| Method | Description |
|---|---|
| `Future<void> handleUpgrade(HttpRequest request, String? localIp)` | Upgrades the HTTP request to a WebSocket. In relay-only mode sends `auth_ok` immediately; in server mode the first message must be `{'type': 'auth', 'token': '...'}`. |
| `void send(WebSocket ws, Map<String, dynamic> msg, [SessionCipher? cipher])` | Sends a JSON message, encrypting with `cipher` if provided. |

## Key behaviors — JSON signaling

All signaling is handled inside `_processJsonMessage`. Encrypted sessions: if a cipher is present, the raw message is expected to be `{'type': 'encrypted', 'iv': ..., 'data': ...}`; it is decrypted before dispatch.

| Message type | Behavior |
|---|---|
| `auth` | Validates the token from `sessions`; sets `authenticated = true` and replies `auth_ok`. In relay mode, always replies `auth_ok`. |
| `key-exchange` | Calls `CryptoService.serverKeyExchange` with the client's public key, stores the cipher on the client, and echoes back the server's public key. |
| `hello` | Registers the client (`ConnectedClient`) in the `clients` map, sends `welcome` with the assigned `clientId`, and calls `broadcastClients`. |
| `set-receiving` | Updates `client.receiving` and calls `broadcastClients`. |
| `rename` | Updates `client.appName` and calls `broadcastClients`. |
| `send-request` | Creates a `TransferSession`, routes the request to the receiver. If the receiver is offline, sends `send-reject` back to the sender. |
| `send-accept` | Routes to the sender (validates that the accept comes from the declared receiver). |
| `send-reject` | Routes to the sender, removes the `TransferSession`. |
| `send-cancel` | Routes to the other party (sender or receiver), removes the `TransferSession`. |
| `send-complete` | Routes to the receiver (validates from sender), removes the `TransferSession`. |

## Key behaviors — binary relay

`_relayBinaryFrame`:
1. If the sender has a cipher, decrypts the frame first.
2. Extracts the `transferId` from the first 36 bytes.
3. Looks up the `TransferSession` to find the receiver.
4. If the receiver has a cipher, re-encrypts the payload for the receiver before forwarding.
5. Otherwise sends the raw payload.

This transparent per-session encryption means sender and receiver can independently negotiate encryption, and the relay re-encrypts when needed without knowing the key material of either side (the relay only knows its own server-side cipher for each session).

- Dependencies: `dart:io`, `dart:convert`, `dart:typed_data`, `CryptoService`, `AppLogger`, `relay_types.dart`.
