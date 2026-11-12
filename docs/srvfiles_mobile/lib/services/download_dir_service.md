# services/download_dir_service.dart

**File:** `lib/services/download_dir_service.dart`

## Purpose

Centralised service that resolves the correct download / received-files directory for the current platform. Eliminates the duplicate `_getDownloadDir()` implementations that previously existed in both `HomeScreen` and `ReceivedFilesService`.

> **Carpeta compartida.** Descargas, archivos recibidos y modo servidor usan una sola carpeta: `Download/SrvFiles`, la misma que el servidor web y la app de escritorio. Sin permisos especiales: desde Android 11 la app ve ahí solo los archivos que creó ella; lo copiado a mano con otra app o lo que quede de una instalación anterior no aparece.

## Exports / Public API

### `DownloadDirService`

| Method | Description |
|---|---|
| `Future<Directory> getDownloadsDir()` | Shared folder for downloads, P2P received files and server mode. The first call moves (once) what was left in the old folders: `SrvFiles/received` and `Documents/SrvFiles/server`. On Android: `/storage/emulated/0/Download/SrvFiles` (falls back to `Documents/SrvFiles` if the standard download dir doesn't exist). On iOS: `<Documents>/SrvFiles`. Creates the directory if it doesn't exist. |
| `Future<Directory> getReceivedDir()` | Same folder as `getDownloadsDir()`. |
| `static Future<void> moveFilesInto(Directory from, Directory to)` | Moves visible files without overwriting (`a (1).txt`) and deletes `from` if it ends up empty. Used by the migration. |

## Key behaviors

- Both methods create their target directories with `recursive: true` if they don't exist.
- Android fallback: if `/storage/emulated/0/Download` doesn't exist (e.g. on emulators without an SD card), `getApplicationDocumentsDirectory()` is used as the base.
- The class is `const`-constructible since it holds no state.
- Dependencies: `dart:io`, `path_provider`.
