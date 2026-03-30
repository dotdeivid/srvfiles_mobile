# services/mobile_server_storage_service.dart

**File:** `lib/services/mobile_server_storage_service.dart`

## Purpose

Manages the file storage directory for the mobile embedded server (server mode). Files are stored under `Documents/SrvFiles/server/`, separate from P2P received files (`Documents/SrvFiles/Recibidos/`). Used exclusively by `RelayHttpHandler` when server mode is active.

## Exports / Public API

### `MobileServerStorageService`

| Constructor | Description |
|---|---|
| `MobileServerStorageService()` | Default constructor; resolves the directory lazily on first use. |
| `MobileServerStorageService.forTesting(Directory dir)` | `@visibleForTesting` factory that injects a pre-built directory for unit tests without touching the real filesystem. |

**Methods:**

| Method | Description |
|---|---|
| `Future<Directory> getDirectory()` | Returns (and caches in `_dir`) the `Documents/SrvFiles/server/` directory, creating it if necessary. |
| `Future<List<FileInfo>> listFiles()` | Lists files sorted by modification date descending. Returns `[]` if the directory doesn't exist yet. Each `FileInfo` has a relative download URL (`/api/files/download/<encodedName>`). |
| `Future<String> saveFile(String fileName, List<int> bytes)` | Sanitises the filename, resolves name conflicts by appending ` (1)`, ` (2)`, etc., writes bytes, and returns the final saved name. Logs success via `AppLogger`. |
| `Future<void> deleteFile(String fileName)` | Deletes the file if it exists; logs a warning if not found. |
| `Future<File?> getFile(String fileName)` | Returns the `File` object if it exists, `null` otherwise (used by `RelayHttpHandler.handleDownload`). |
| `Future<DiskStats> getStats()` | Sums sizes of all files for `used`. Obtains `total` and `free` via `MethodChannel('com.srvfiles/disk_space')` invoking `getFreeDiskSpace` / `getTotalDiskSpace` from `MainActivity.kt` (Android `StatFs`). Logs a warning on channel failure; values default to `0`. |

## Key behaviors

- **`_sanitize`**: replaces `[/\\:*?"<>|]` and sequences of `..` with `_`, trims whitespace, defaults to `'archivo'` if the result is empty. Prevents path traversal.
- **Name conflict resolution**: appends ` (N)` before the extension to generate a unique name (e.g. `foto.jpg` → `foto (1).jpg`).
- **Platform channel for disk space**: uses `MethodChannel('com.srvfiles/disk_space')`. This avoids third-party packages incompatible with the modern Android Gradle Plugin. The matching Kotlin handler is in `MainActivity.kt` using `StatFs`.
- **`forTesting` constructor**: `@visibleForTesting` — sets `_dir` directly, bypassing `getApplicationDocumentsDirectory()`.
- Dependencies: `dart:io`, `flutter/services`, `path_provider`, `FileInfo`, `DiskStats`, `AppLogger`.
