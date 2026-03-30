# services/relay/relay_types.dart

**File:** `lib/services/relay/relay_types.dart`

## Purpose

Shared data classes used internally by the embedded relay subsystem (`EmbeddedRelay`, `RelayWsHandler`, `RelayAuth`). Keeps type definitions in one place instead of scattered across handler files.

## Exports / Public API

### `ConnectedClient`

Represents a WebSocket client currently connected to the embedded relay.

| Field | Type | Description |
|---|---|---|
| `ws` | `WebSocket` | The live WebSocket connection. |
| `clientId` | `String` | UUID assigned at connection time. |
| `appName` | `String` | Mutable display name (updated on `rename` messages). |
| `receiving` | `bool` | Whether this client is accepting incoming transfers. |
| `ip` | `String` | Resolved IP address (loopback is replaced with the LAN IP). |
| `deviceType` | `String` | `'mobile'` or `'desktop'`. |
| `isOwner` | `bool` | `true` if the client connected from localhost (the phone itself). |
| `cipher` | `SessionCipher?` | AES-256-GCM cipher after a successful key exchange; `null` if unencrypted. |

### `TransferSession`

Tracks an active file transfer routed through the relay.

| Field | Type | Description |
|---|---|---|
| `transferId` | `String` | UUID from the originating `send-request`. |
| `senderClientId` | `String` | Client ID of the sender. |
| `receiverClientId` | `String` | Client ID of the receiver. |
| `fileName` | `String` | File name. |
| `fileSize` | `int` | File size in bytes. |
| `mimeType` | `String` | MIME type. |

### `RateEntry`

Per-IP authentication rate-limiting state.

| Field | Type | Description |
|---|---|---|
| `count` | `int` | Number of failed attempts since last reset. |
| `blockedUntil` | `DateTime` | Block expiry time; compared against `DateTime.now()` in `RelayAuth`. |

## Key behaviors

- All three classes are mutable where needed (`appName`, `receiving`, `cipher`, `count`, `blockedUntil`).
- `ConnectedClient.isOwner` is determined at connection time by checking whether the remote address is loopback (`127.0.0.1`, `::1`, or empty).
- `SessionCipher` is imported from `crypto_service.dart`.
