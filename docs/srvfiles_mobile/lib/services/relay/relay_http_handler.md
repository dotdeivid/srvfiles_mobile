# services/relay/relay_http_handler.dart

**File:** `lib/services/relay/relay_http_handler.dart`

## Purpose

Handles all HTTP REST endpoints for the embedded relay's server mode: file listing, multipart upload, file download, file deletion, disk stats, server config, and static frontend file serving. All file-storage operations delegate to `MobileServerStorageService`.

## Exports / Public API

### `RelayHttpHandler`

| Member | Description |
|---|---|
| `MobileServerStorageService? storage` | Set by `EmbeddedRelay.startServerMode`. Must be non-null before calling any file-related handler. |
| `VoidCallback? onFilesChanged` | Called after upload and delete operations to trigger `files-changed` WebSocket broadcast. Set by `EmbeddedRelay` constructor. |
| `Future<void> handleListFiles(HttpRequest req)` | `GET /api/files` — returns `{'files': [...], 'count': N}`. |
| `Future<void> handleUpload(HttpRequest req)` | `POST /api/files/upload` — parses `multipart/form-data`, saves each `filename` part via `storage.saveFile`, returns saved names. |
| `Future<void> handleDownload(HttpRequest req, String fileName)` | `GET /api/files/download/<name>` — streams the file to the response with the correct MIME type and `content-disposition`. |
| `Future<void> handleDeleteFile(HttpRequest req, String fileName)` | `DELETE /api/files/<name>` — deletes via `storage.deleteFile`. |
| `Future<void> handleStats(HttpRequest req)` | `GET /api/files/stats` — returns `{'total', 'used', 'free'}` bytes. |
| `void handleConfig(HttpRequest req, {String? localIp, int port})` | `GET /api/config` — returns server metadata for the frontend. |
| `void handleHealth(HttpRequest req, {String? deviceName, bool serverModeActive, int clientCount})` | `GET /api/health` — always public; returns `{'status': 'ok', 'app': 'srvfiles', 'relay': true, 'serverMode': ..., 'clients': N}`. |
| `Future<void> handleStaticFile(HttpRequest req)` | Serves files from `assets/www/` via `rootBundle.load`. Falls back to `index.html` for unknown paths (SPA routing). |

### `typedef VoidCallback = void Function()` (local re-export)

Defined at the bottom of the file to avoid importing `package:flutter/foundation.dart` in a non-UI file.

## Key behaviors

- **Upload parsing**: uses `MimeMultipartTransformer` from the `mime` package to parse `multipart/form-data`. Only parts with a `filename` parameter in `content-disposition` are saved.
- **Download streaming**: uses `file.openRead().pipe(req.response)` for memory-efficient streaming of large files.
- **Static MIME detection**: `_staticMimeType` maps common web extensions (`html`, `js`, `mjs`, `css`, `svg`, `png`, `ico`, `woff2`, `woff`, `ttf`, `json`) to their MIME types; unknown extensions fall back to `application/octet-stream`.
- **Config response**: `maxFileSizeMb` is always `0` (unlimited) for the mobile server. `frontendPort == port` because mobile serves both API and frontend on the same port.
- Dependencies: `dart:io`, `dart:convert`, `flutter/services` (rootBundle), `mime`, `MobileServerStorageService`.
