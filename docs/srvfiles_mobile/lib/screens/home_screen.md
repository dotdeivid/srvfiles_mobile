# screens/home_screen.dart

**File:** `lib/screens/home_screen.dart`

## Purpose

Main screen of the app. Composes `FilesController`, `TransferController`, and `ServerController` (all `ChangeNotifier`s) to display server files, P2P online clients, active transfer progress, received files, and server info. The screen itself is thin presentation logic — all business logic lives in the three controllers.

## Exports / Public API

### `HomeScreen extends StatefulWidget`

**Constructor parameters:**

| Parameter | Type | Description |
|---|---|---|
| `serverUrl` | `String?` | URL of an external SrvFiles server to connect to, or `null` for relay-only / server mode. |
| `autoServerMode` | `bool` | If `true`, server mode is activated automatically when the screen initialises (default `false`). |

## State (`_HomeScreenState`)

**Controllers:**

| Field | Description |
|---|---|
| `FilesController _filesCtrl` | Owns file list, upload, download, search, disk stats. |
| `TransferController _transferCtrl` | Owns WebSocket connection, P2P send/receive, device name. |
| `ServerController _serverCtrl` | Owns embedded relay lifecycle, server mode, direct LAN scanning. |

**Computed getters:**

| Getter | Description |
|---|---|
| `bool _hasServer` | `widget.serverUrl != null` — connected to an external server. |
| `bool _isServer` | `_hasServer || _serverCtrl.relay.isServerMode` — any source of files to manage. |
| `bool _isDirectMode` | `!_hasServer && !_serverCtrl.relay.isServerMode` — P2P only, no file storage. |

## Key behaviors — lifecycle

- **`initState`**: creates all three controllers; wires `initDirectPoolCallbacks`; if `_hasServer` sets up `FilesService` immediately; then calls `_initTransfer` (which calls `_connectWebSocket`). For relay-only, calls `_startRelay()` which starts the relay, then `_initTransfer`.
- **`didChangeAppLifecycleState`**: on `paused` starts the Android foreground service; on `resumed` stops it and reconnects the WebSocket if disconnected.
- **`dispose`**: removes the lifecycle observer, disposes all three controllers, cancels the search controller.

## Key behaviors — server mode

- `_activateServerMode()` delegates to `_serverCtrl.activateServerMode(...)`, passing a `checkWarning` callback that shows `ServerModeWarningDialog`. On success, calls `_filesCtrl.setService(...)` and `_filesCtrl.initialLoad()`.
- The relay is started in relay-only mode first; server mode is activated separately (either automatically via `autoServerMode` or manually via the UI).

## Key behaviors — auth flow

- External servers with PIN: `TransferController.onAuthRequired` calls `_handleAuthRequired`, which shows `PinEntryDialog`. On success, `POST /api/auth` obtains a token, sets it on `_transferCtrl.transferService` and `_filesCtrl.filesService`, then reconnects and loads files.
- Local relay in server mode: `ServerController.autoAuthWithRelay` handles re-auth on reconnect.

## Key behaviors — direct mode

- When neither server nor server mode is active, `_serverCtrl.startDirectScanning()` polls LAN every 5 seconds for discoverable relay devices.
- Tapping a direct device calls `_serverCtrl.getDirectConnection(url, deviceName)` and then `_transferCtrl.sendFileViaService(...)`.

## Key behaviors — ConnectSheet

The wifi icon in the header opens `ConnectSheet` as a `showModalBottomSheet`. The sheet receives all server/relay state as parameters and calls `onConnect(url)` or `onDisconnect()`. `onDisconnect` navigates back to `SplashScreen` via `pushReplacement`.

## Key behaviors — received files

`_receivedFiles` is loaded from `ReceivedFilesService` on init and refreshed whenever `onFilesChanged` fires (after a P2P receive completes). Displayed in a separate section below the server files list.

- Dependencies: all three controller classes, `ConnectSheet`, all widget files, `SplashScreen`, `PreviewService`, `share_plus`, `open_filex`.
