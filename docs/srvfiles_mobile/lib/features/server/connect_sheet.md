# features/server/connect_sheet.dart

**File:** `lib/features/server/connect_sheet.dart`

## Purpose

A modal bottom sheet that lets the user view the current server info, scan for other SrvFiles servers on the LAN, or connect to one manually by entering an IP address. It adapts its presentation depending on whether the device is acting as a local relay server or as a client connected to an external server.

## Exports / Public API

### `ConnectSheet extends StatefulWidget`

**Constructor parameters:**

| Parameter | Type | Description |
|---|---|---|
| `onConnect` | `void Function(String url)` | Called with the selected URL when the user taps a discovered server or submits the manual IP. |
| `onDisconnect` | `VoidCallback` | Called when the user taps "Desconectarse". Navigates back to the splash screen. |
| `currentServerUrl` | `String?` | URL of the currently connected external server, or `null`. |
| `webUrl` | `String?` | Web URL of the connected server (shown as a second URL row if different from the server URL). |
| `relayIp` | `String?` | Local IP address of this device's embedded relay (shown when acting as local server). |
| `relayPort` | `int` | Port of the embedded relay (default `3001`). |
| `relayPin` | `String?` | Current PIN for the local relay's server mode (displayed in the info card). |
| `isRelayServer` | `bool` | Whether this device is running the embedded relay (default `false`). |
| `isRelayRunning` | `bool` | Whether the relay is currently started (default `false`). |

## Key behaviors

- **LAN scan**: `DiscoveryService().scanLan()` is called in `initState` (unless acting as local-only server) and can be triggered again with the "Volver a escanear" button.
- **Manual IP**: The text field normalises input by prepending `http://` if missing and appending `:3001` if no port is present.
- **Three display modes**:
  1. *Local server* (`isRelayServer && currentServerUrl == null`): shows a card with the local IP:port, badge "Activo", and the PIN.
  2. *Connected to external server* (`currentServerUrl != null`): shows a card with the remote address, badge "Conectado"; LAN scan section still shown below.
  3. *Not connected*: shows only the scan results and manual input.
- **Server info card**: built by `_buildServerInfoCard`; each URL/PIN row uses `_buildUrlRow` with a fixed 52 px label column and a clipboard copy button.
- Tapping "Desconectarse" pops the sheet and calls `onDisconnect`.
- Dependencies: `DiscoveryService`, `AppColors`, `AppSpacing`.
