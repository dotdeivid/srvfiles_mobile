# services/files_service.dart

**File:** `lib/services/files_service.dart`

## Purpose

HTTP client for all file operations against the SrvFiles backend (or the embedded relay in server mode). Encapsulates network calls and returns typed models. Supports session-token authentication via the `X-SrvFiles-Token` header.

## Exports / Public API

### `FilesService`

**Constructor:** `FilesService(ApiConfig config)`

| Member | Description |
|---|---|
| `void setToken(String token)` | Stores a session token included as `X-SrvFiles-Token` in all subsequent requests. |
| `String? get sessionToken` | Exposes the current token (used by `PreviewService`). |
| `Map<String, String> get authHeaders` | Returns `{'X-SrvFiles-Token': token}` if a token is set, or `{}`. Public for use in direct HTTP calls (e.g. `FilesController.download`). |
| `Future<List<FileInfo>> getFiles()` | `GET /api/files` — throws on non-200. |
| `Future<void> uploadFile(File file, {void Function(double)? onProgress})` | `POST /api/files/upload` (multipart, field name `'files'`). Uses streaming with `file.openRead()` to avoid loading large files into memory. Throws on non-200. |
| `Future<void> uploadFiles(List<File> files, {void Function(double)? onProgress})` | Same as `uploadFile` but sends all files in a single multipart request. |
| `Future<bool> deleteFile(String filename)` | `DELETE /api/files/<encodedName>` — returns `true` on 200, `false` otherwise. |
| `Future<DiskStats> getStats()` | `GET /api/files/stats` — throws on non-200. |
| `Future<AppConfig> getConfig()` | `GET /api/config` — throws on non-200. |
| `String getDownloadUrl(String filename)` | Delegates to `_config.downloadUrl(filename)` — no network call. |
| `Future<bool> healthCheck()` | `GET /api/health` with 3 s timeout. Returns `false` on any error or non-200 status. |

## Key behaviors

- All methods that make network requests include `_authHeaders` so they work on both unauthenticated (relay-only) and PIN-protected (server mode) endpoints.
- Error handling: all mutating methods throw `Exception` on non-200 status; `healthCheck` and `deleteFile` return a boolean instead.
- Logging: all methods log at `debug`/`info`/`warn`/`error` levels via `AppLogger.instance`.
- Dependencies: `http`, `ApiConfig`, `FileInfo`, `DiskStats`, `AppConfig`, `AppLogger`.
