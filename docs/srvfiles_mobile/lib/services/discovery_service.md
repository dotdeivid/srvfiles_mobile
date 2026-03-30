# services/discovery_service.dart

**File:** `lib/services/discovery_service.dart`

## Purpose

Scans the local subnet for SrvFiles server instances. Used by `ConnectSheet`, `SplashScreen`, and `ServerController` to auto-discover servers and direct-mode relay devices.

## Exports / Public API

### `DiscoveredServer`

| Field | Description |
|---|---|
| `String ip` | Hostname/IP of the server. |
| `String url` | Full base URL, e.g. `http://192.168.1.5:3001`. |
| `String appName` | Display name from `/api/health`. |

`factory DiscoveredServer.fromJson(Map<String, dynamic>)` — for deserialising results from `scanNetwork`.

### `DiscoveryService`

| Method | Description |
|---|---|
| `Future<DiscoveredServer?> probe(String serverUrl, {Duration timeout = 3s})` | GETs `<serverUrl>/api/health`. Returns a `DiscoveredServer` if the response is `200`, `status == 'ok'`, and `app.toLowerCase() == 'srvfiles'`. Returns `null` on any error or mismatch. |
| `Future<bool> tryConnect(String serverUrl)` | Convenience wrapper around `probe` that returns a `bool`. Used by `SplashScreen` to quickly re-check the last known server. Logs errors via `AppLogger`. |
| `Future<List<DiscoveredServer>> scanLan()` | Determines the local subnet from the device's LAN IP (see `_getLocalIp`), then fires 254 parallel `probe` calls (each with 800 ms timeout) skipping the device's own IP. Returns all successful probes. |
| `Future<List<DiscoveredServer>> scanNetwork(String serverUrl)` | Server-assisted scan: calls `<serverUrl>/api/discovery/scan` (15 s timeout) and deserialises the result list. Used as a fallback when the local scan isn't possible. |

## Key behaviors

- **`probe` timeout**: 800 ms in `scanLan`, 3 s in direct callers (configurable parameter).
- **`app` field case-insensitive**: `json['app'].toLowerCase() == 'srvfiles'` so both `'srvfiles'` (backend) and `'SrvFiles'` (mobile relay) are matched.
- **`appName` resolution**: prefers `json['appName']`, falls back to `json['app']`, then `'SrvFiles'`.
- **`_getLocalIp`**: iterates `NetworkInterface.list(IPv4, noLoopback)`, prefers RFC-1918 ranges (`192.168.*`, `10.*`, `172.*`), falls back to any non-loopback address.
- **`Future.wait`**: all 254 probes run concurrently — total scan time ≈ slowest probe (≈ 800 ms), not 254 × 800 ms.
- Dependencies: `dart:io`, `http`, `AppLogger`.
