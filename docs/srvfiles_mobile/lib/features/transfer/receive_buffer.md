# features/transfer/receive_buffer.dart

**File:** `lib/features/transfer/receive_buffer.dart`

## Purpose

A plain data class that accumulates incoming binary chunks during a P2P file transfer. One `ReceiveBuffer` is created per active incoming transfer when the user accepts a transfer request, and discarded once the transfer completes or is cancelled.

## Exports / Public API

### `ReceiveBuffer`

| Field | Type | Description |
|---|---|---|
| `chunks` | `List<Uint8List>` | Accumulated binary chunks from the sender, in arrival order. |
| `received` | `int` | Total bytes accumulated so far (updated by `TransferController.handleBinaryChunk`). |
| `total` | `int` | Expected total file size in bytes (from the original `send-request` message). |
| `fileName` | `String` | The name of the file being received. |
| `mimeType` | `String` | MIME type reported by the sender. |

## Key behaviors

- `received >= total` signals that the transfer is complete; `TransferController` uses this condition to assemble the final file from `chunks`.
- Chunks are assembled by iterating `chunks` in order: `Uint8List(total)` is filled with `setRange` for each chunk.
- No encryption logic here — chunks arrive already decrypted by `TransferService`.
- No external dependencies (only `dart:typed_data`).
