# services/direct_transfer_pool.dart

**File:** `lib/services/direct_transfer_pool.dart`

## Purpose

Manages a pool of reusable WebSocket connections to remote relay servers for device-to-device ("direct mode") file transfers. In direct mode the mobile app is not connected to any external server, so it opens an ad-hoc connection to each discovered relay, sends/receives files through it, and closes the connection after a period of inactivity.

## Exports / Public API

### `DirectPeerConnection`

Simple value object returned by the pool when a connection is ready.

| Field | Description |
|---|---|
| `TransferService service` | The active `TransferService` for this connection. |
| `String targetClientId` | The `clientId` of the relay owner (the peer to send files to). |

### `DirectTransferPool`

| Member | Description |
|---|---|
| `Future<DirectPeerConnection?> getConnection(String targetUrl, String deviceName)` | Returns an existing live connection to `targetUrl`, or opens a new one. New connections register the device, wait (up to 5 s) for the relay to send a `clients` message and identify the owner's `clientId`, then store the entry in the pool. Returns `null` on timeout or connection failure. |
| `void touch(String targetUrl)` | Resets the inactivity timer for a pool entry (call after each successful transfer). |
| `void disposeAll()` | Closes all pooled connections and clears the pool. |
| `void Function(IncomingTransferRequest)? onSendRequest` | Delegated to every pooled `TransferService`. |
| `void Function(String)? onSendAccept` | Delegated to every pooled `TransferService`. |
| `void Function(String, String?)? onSendReject` | Delegated. |
| `void Function(String)? onSendCancel` | Delegated. |
| `void Function(String)? onSendComplete` | Delegated. |
| `void Function(String, Uint8List)? onBinaryChunk` | Delegated. |

## Key behaviors

- **Inactivity timeout**: 60 seconds (`_inactivityTimeout`). The timer is reset by `touch()` after each transfer and restarted on every `getConnection` call that reuses an existing entry.
- **Owner discovery**: the relay owner is identified by checking `isOwner == true` in the `clients` list; if no client has `isOwner`, the first client that is not the caller itself is used.
- **Connection lifecycle**: when the underlying `TransferService` disconnects, `_close(targetUrl)` is called automatically (wired via `onDisconnected`), removing the stale entry from the pool.
- **Auth flow**: the pool connects in relay-only mode; `onAuthOk` fires immediately (no PIN), causing `register` and `setReceiving(true)` to be sent.
- Dependencies: `TransferService`, `ApiConfig`, `TransferClient`, `IncomingTransferRequest`, `AppLogger`.
