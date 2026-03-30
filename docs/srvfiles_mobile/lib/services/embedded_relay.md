# services/embedded_relay.dart

**File:** `lib/services/embedded_relay.dart`

## Purpose

Mini HTTP + WebSocket relay server embedded in the mobile app. Runs on `0.0.0.0` so both the local device and LAN clients can reach it. Operates in two modes:

- **Relay only** (default): exposes `GET /api/health` and `WebSocket /ws` only; any device can connect and transfer files P2P without authentication.
- **Server mode**: adds a full REST API for file management + PIN authentication + static frontend serving from `assets/www/`.

Delegates work to three sub-handlers:
- `RelayAuth` — auth endpoints, rate limiting, session tokens.
- `RelayHttpHandler` — REST file endpoints, static file serving.
- `RelayWsHandler` — WebSocket upgrade, signaling, binary relay, key exchange.

## Exports / Public API

### `EmbeddedRelay`

**Getters:**

| Getter | Description |
|---|---|
| `bool isRunning` | `true` when the `HttpServer` is bound and listening. |
| `bool isServerMode` | `true` after `startServerMode()` and before `stopServerMode()`. |
| `String? localIp` | Best available LAN IPv4 address (prefers `192.168.x.x`). `null` before `start()`. |
| `int port` | Bound port (default 3001, incremented on collision). |
| `String? currentPin` | Plain-text PIN while server mode is active. Sourced from `RelayAuth.currentPin`. |
| `String? url` | `'http://<localIp>:<port>'` or `null` if not started. |

**Methods:**

| Method | Description |
|---|---|
| `void setDeviceName(String name)` | Sets the name returned by `/api/health`. |
| `Future<void> start({int port = 3001})` | Binds the HTTP server. Tries up to 5 successive ports if the requested port is busy. Port `0` lets the OS pick a free port. |
| `Future<String> startServerMode()` | Activates server mode: creates `MobileServerStorageService` and `PinService`, generates and stores the PIN, wires the pin into `RelayAuth`, and returns the plain-text PIN. |
| `Future<void> stopServerMode()` | Deactivates server mode, clears sessions/rate limits/PIN, and disposes storage and pin service. |
| `Future<void> stop()` | Calls `stopServerMode`, closes all WebSocket connections, and closes the `HttpServer`. |

## Key behaviors — request router (`_handleRequest`)

| Route | Auth required | Handler |
|---|---|---|
| `GET /api/health` | No | `RelayHttpHandler.handleHealth` |
| `/ws` | No (auth via WS protocol) | `RelayWsHandler.handleUpgrade` |
| `POST /api/auth` | No | `RelayAuth.handleAuth` |
| `GET /api/pin` | No | `RelayAuth.handlePin` |
| `GET /api/files` | Yes (server mode only) | `RelayHttpHandler.handleListFiles` |
| `POST /api/files/upload` | Yes | `RelayHttpHandler.handleUpload` |
| `GET /api/files/download/<name>` | Yes | `RelayHttpHandler.handleDownload` |
| `DELETE /api/files/<name>` | Yes | `RelayHttpHandler.handleDeleteFile` |
| `GET /api/files/stats` | Yes | `RelayHttpHandler.handleStats` |
| `GET /api/config` | Yes | `RelayHttpHandler.handleConfig` |
| Everything else | No | `RelayHttpHandler.handleStaticFile` |

- CORS headers (`Access-Control-Allow-Origin: *`) are set on all responses.
- Trailing slashes on paths are normalised before routing.
- The `sessions` map is shared between `RelayAuth` and `RelayWsHandler` by reference so WS token validation works without a direct coupling.

## Key behaviors — broadcasts

- `_broadcastClients()`: sends `{'type': 'clients', 'clients': [...]}` to all connected WS clients (with per-client encryption if the session has a cipher).
- `_broadcastFilesChanged()`: sends `{'type': 'files-changed'}` to all clients after upload/delete.

## Key behaviors — local IP detection

`_getLocalIp` iterates `NetworkInterface.list` (IPv4, no loopback), prefers addresses starting with `192.168.`, falls back to the first non-loopback address.

## Key behaviors — UUID generation

`_generateUuid` uses `Random.secure()` to generate RFC 4122 v4 UUIDs (passed to `RelayAuth.handleAuth` and used for client IDs in `RelayWsHandler`).
