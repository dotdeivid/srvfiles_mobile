# features/transfer/transfer_controller.dart

**File:** `lib/features/transfer/transfer_controller.dart`

## Purpose

`ChangeNotifier` that owns all P2P transfer state: WebSocket connection lifecycle, send/receive flows, chunk buffering, progress tracking, device naming, and cancellation. Extracted from `_HomeScreenState` to keep the screen widget focused on presentation.

## Exports / Public API

### Typedefs

| Typedef | Signature | Description |
|---|---|---|
| `ShowSnackBar` | `void Function(String, {bool isError, String? actionLabel, VoidCallback? onAction})` | Delegate for showing snack bars from the screen. |
| `ShowIncomingDialog` | `Future<bool?> Function(IncomingTransferRequest)` | Delegate for showing the incoming-transfer accept dialog. |
| `OnAuthRequired` | `void Function()` | Called when the WebSocket closes with code `4401` (token expired). |

### `TransferController extends ChangeNotifier`

**Constructor parameters:**

| Parameter | Description |
|---|---|
| `TransferService transferService` | The WebSocket client instance. |
| `DeviceNameService deviceNameService` | For resolving / persisting the device name. |
| `NotificationService notificationService` | For push notifications on incoming transfers and completions. |
| `ReceivedFilesService receivedFilesService` | For saving assembled files to disk. |
| `ShowSnackBar? showSnackBar` | UI callback. |
| `ShowIncomingDialog? showIncomingDialog` | UI callback. |
| `OnAuthRequired? onAuthRequired` | UI callback for PIN re-entry. |
| `VoidCallback? onFilesChanged` | Called after a receive completes (so the files list can refresh). |

**Public state:**

| Field | Description |
|---|---|
| `String? myClientId` | This client's ID assigned by the relay after `welcome`. |
| `List<TransferClient> onlineClients` | Live list of clients from the relay's `clients` messages. |
| `ActiveTransfer? activeTransfer` | Currently active send or receive, or `null` when idle. |
| `String deviceName` | The device's display name for P2P. |
| `PendingSend? pendingSend` | Read-only access to the pending outgoing send (for cancel logic). |

**Key methods:**

| Method | Description |
|---|---|
| `Future<void> initTransfer()` | Wires all `TransferService` callbacks (`onWelcome`, `onClientsUpdate`, `onSendRequest`, etc.) and resolves the device name. |
| `Future<void> connectWebSocket(ApiConfig, {hasServer, autoServerMode, onAuthOk})` | Connects the WebSocket; if a token is present, auth is handled automatically; `onAuthOk` is called after key exchange. |
| `Future<void> ensureDeviceName()` | Loads the stored name; on first launch generates a random name and persists it. |
| `Future<void> sendFile(String clientId, String peerName)` | Prompts file picker, creates `PendingSend`, sets `activeTransfer` (waiting), and sends `send-request`. |
| `Future<void> sendFileViaService({...})` | Same as `sendFile` but routes through a specific `TransferService` instance (direct pool). |
| `Future<void> handleSendAccept(String transferId)` | Reads file bytes, calls `transferService.sendFile` with progress updates, clears state on completion. |
| `void acceptTransfer(IncomingTransferRequest)` | Creates a `ReceiveBuffer`, sets `activeTransfer` (receiving), sends `send-accept`. |
| `void handleBinaryChunk(String transferId, Uint8List data)` | Appends chunk to the correct `ReceiveBuffer` and updates progress. |
| `void cancelTransfer()` | Sends `send-cancel` through the correct service, clears all state. |
| `Future<void> rename(String newName)` | Persists the new name and sends a `rename` message to the relay. |

## Key behaviors

- Holds a `Map<String, ReceiveBuffer> _receiveBuffers` keyed by `transferId`; multiple concurrent receives are theoretically supported.
- On `send-complete`, assembles bytes from `ReceiveBuffer.chunks` using `setRange`, saves via `ReceivedFilesService.saveFile`, fires a notification, and calls `onFilesChanged`.
- On WebSocket disconnect, resets `myClientId`, `onlineClients`, and `activeTransfer`.
- `cancelTransfer` uses `_pendingSend?.service ?? transferService` so it cancels through the correct connection in direct mode.
- `dispose` calls `transferService.dispose()` to close the WebSocket cleanly.
- Dependencies: `TransferService`, `DeviceNameService`, `NotificationService`, `ReceivedFilesService`, `FilesController.generateTransferId`, `ReceiveBuffer`, `PendingSend`.
