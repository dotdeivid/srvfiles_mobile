# services/download_dir_service.dart

**File:** `lib/services/download_dir_service.dart`

## Purpose

Centralised service that resolves the correct download / received-files directory for the current platform. Eliminates the duplicate `_getDownloadDir()` implementations that previously existed in both `HomeScreen` and `ReceivedFilesService`.

## Exports / Public API

### `DownloadDirService`

| Method | Description |
|---|---|
| `Future<Directory> getDownloadsDir()` | Returns the directory where files downloaded from the server are saved. On Android: `/storage/emulated/0/Download/SrvFiles` (falls back to `Documents/SrvFiles` if the standard download dir doesn't exist). On iOS: `<Documents>/SrvFiles`. Creates the directory if it doesn't exist. |
| `Future<Directory> getReceivedDir()` | Returns the directory where P2P-received files are saved. Same base directory logic as `getDownloadsDir`, but the final subdirectory is `SrvFiles/Recibidos`. |

## Key behaviors

- Both methods create their target directories with `recursive: true` if they don't exist.
- Android fallback: if `/storage/emulated/0/Download` doesn't exist (e.g. on emulators without an SD card), `getApplicationDocumentsDirectory()` is used as the base.
- The class is `const`-constructible since it holds no state.
- Dependencies: `dart:io`, `path_provider`.
