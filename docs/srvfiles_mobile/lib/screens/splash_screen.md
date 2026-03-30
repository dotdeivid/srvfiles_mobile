# screens/splash_screen.dart

**File:** `lib/screens/splash_screen.dart`

## Purpose

Initial screen. Scans the LAN for SrvFiles servers, shows discovered servers for quick selection, and provides manual IP entry, "direct send" mode, and "use this device as server" options.

## Exports / Public API

### `SplashScreen extends StatefulWidget`

No constructor parameters.

## State (`_SplashScreenState`)

| Field | Description |
|---|---|
| `DiscoveryService _discoveryService` | Used for all probe/scan operations. |
| `bool _searching` | `true` while a scan is in progress (spinner shown, buttons disabled). |
| `String? _error` | Error message displayed below the input. |
| `TextEditingController _ipController` | Manual IP input. |
| `List<DiscoveredServer> _foundServers` | Accumulated discovered servers (last-known + full scan merged without duplicates). |

## Key behaviors — `_scan()`

Two-phase discovery:
1. **Last known server probe**: reads `'srvfiles-last-server'` from `SharedPreferences` and calls `_discoveryService.probe(url)`. If it responds, adds it to `_foundServers` immediately so the user sees it before the full scan completes.
2. **Full LAN scan**: calls `_discoveryService.scanLan()` (254 parallel probes). Results are merged with phase-1 results, deduplicating by URL.

The scan does **not** auto-navigate — the user always taps to connect.

## Key behaviors — navigation

| Method | Destination |
|---|---|
| `_onServerSelected(url)` | Saves the URL to `'srvfiles-last-server'` then navigates to `HomeScreen(serverUrl: url)`. |
| `_onSkipServer()` | Navigates to `HomeScreen(serverUrl: null)` — direct P2P relay mode. |
| `_onBeServer()` | Navigates to `HomeScreen(serverUrl: null, autoServerMode: true)` — activates server mode immediately. |

All three use `pushReplacement` so the splash screen is removed from the navigation stack.

## Key behaviors — manual connect

`_connectManual()`:
1. Normalises the input (prepends `http://`, appends `:3001` if no port).
2. Calls `_discoveryService.tryConnect(url)` to verify the server is reachable.
3. If reachable: calls `_onServerSelected(url)`.
4. If not: sets `_error` with "No se pudo conectar a ...".

## Key behaviors — UI

- **Discovered server list** (`_buildServerList`): shown only when `_foundServers.isNotEmpty`. Each row is a `_ServerRow` widget with the server's name, IP, and a "Conectar" `TextButton`. Rows are disabled (taps blocked) while `_searching` is `true`.
- **"Buscando servidores..."** spinner replaces the "Ingresá la IP" label while scanning.
- **Three action buttons**: "Conectar" (ElevatedButton), "Envío directo" (OutlinedButton), "Usar este dispositivo como servidor" (TextButton). All disabled while `_searching`.
- **Hero animation**: the logo container uses `tag: 'srvfiles-logo'` for a smooth transition to `HomeScreen` if a matching Hero is present there.

## Private widget — `_ServerRow`

Renders a single discovered server: pulsing dot, computer icon, `appName`, IP, and a "Conectar" button. Disabled (null `onTap`) while `_searching`.

- Dependencies: `DiscoveryService`, `AppLogger`, `SharedPreferences`, `HomeScreen`, `GradientText`, `PulsingDot`.
