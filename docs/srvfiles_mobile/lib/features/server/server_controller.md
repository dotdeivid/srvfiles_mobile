# features/server/server_controller.dart

**File:** `lib/features/server/server_controller.dart`

## Purpose

`ChangeNotifier` that manages the embedded relay lifecycle, server mode activation/deactivation, and direct-mode device scanning. Owns the `EmbeddedRelay` and `DirectTransferPool` instances. Extracted from `_HomeScreenState`.

## Exports / Public API

### `ServerController extends ChangeNotifier`

**Constructor:**
```dart
ServerController({required EmbeddedRelay relay, required DirectTransferPool directPool})
```

**Public state:**

| Field | Description |
|---|---|
| `EmbeddedRelay relay` | The embedded relay instance (read-only access for callers). |
| `List<DiscoveredServer> directDevices` | LAN devices discovered during direct-mode scanning. |
| `bool directScanning` | True while a LAN scan is in progress. |
| `bool get isDirectMode` | `true` when not in server mode (i.e. `!relay.isServerMode`). |

**Key methods:**

| Method | Description |
|---|---|
| `Future<String?> startRelay()` | Starts the embedded relay. Returns the relay URL on success, `null` on error. |
| `Future<String?> activateServerMode({checkWarning, transferService, setFilesService})` | Checks the warning-dismissed preference; if not dismissed, calls `checkWarning()` (returns `false` → cancelled). Starts server mode on the relay, auto-authenticates via `POST /api/auth` to the local relay, applies the token to `transferService`, and creates a `FilesService` pointing at `127.0.0.1:<port>`. Returns the PIN or `null` on cancel/error. |
| `Future<bool> autoAuthWithRelay(TransferService, FilesService?)` | Re-authenticates to the local relay using `relay.currentPin`. Called on reconnect when the relay is already in server mode. Returns `true` on success. |
| `void initDirectPoolCallbacks({...})` | Wires all transfer-event callbacks from the pool to the caller's handlers. |
| `void startDirectScanning()` | Runs `scanForDirectDevices()` immediately and every 5 seconds. |
| `void stopDirectScanning()` | Cancels the scan timer and clears `directDevices`. |
| `Future<void> scanForDirectDevices()` | Runs `DiscoveryService().scanLan()`, updates `directDevices`. |
| `Future<DirectPeerConnection?> getDirectConnection(String url, String deviceName)` | Delegates to `directPool.getConnection`. |
| `void touchPool(String url)` | Resets the pool entry's inactivity timer. |

## Key behaviors

- `activateServerMode` reads `SharedPreferences` key `'server_mode_warning_dismissed'` to skip the warning dialog on subsequent activations.
- Auto-auth: after `relay.startServerMode()`, the controller immediately calls `POST http://127.0.0.1:<port>/api/auth` with the fresh PIN to obtain a session token for `TransferService` and `FilesService`.
- `dispose` cancels the scan timer, calls `directPool.disposeAll()`, and `relay.stop()`.
- Dependencies: `EmbeddedRelay`, `DirectTransferPool`, `FilesService`, `TransferService`, `DiscoveryService`, `AppLogger`, `http`, `shared_preferences`.
