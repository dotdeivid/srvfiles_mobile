# features/transfer/pending_send.dart

**File:** `lib/features/transfer/pending_send.dart`

## Purpose

Holds the state of a file send that is waiting for the peer to accept. Created when the user picks a file and a `send-request` is dispatched; discarded once the peer sends `send-accept` (transfer starts) or `send-reject`/`send-cancel`.

## Exports / Public API

### `PendingSend`

| Field | Type | Description |
|---|---|---|
| `transferId` | `String` | UUID identifying this transfer, matches the `send-request` message. |
| `file` | `File` | The file on disk to be sent. Read with `readAsBytes()` once the peer accepts. |
| `peerId` | `String` | The `clientId` of the intended recipient. |
| `service` | `TransferService` | The service instance to stream chunks through — either the main `TransferService` or a pool connection from `DirectTransferPool`. |

## Key behaviors

- `service` can be any `TransferService` instance, allowing `TransferController` to route both local-relay and direct-pool sends through the same accept/chunk path.
- `TransferController` holds at most one `PendingSend` at a time (`_pendingSend`); attempting to send while another send is pending is a no-op.
- No external dependencies beyond `dart:io` and `TransferService`.
