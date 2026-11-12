# services/received_files_service.dart

**File:** `lib/services/received_files_service.dart`

## Purpose

Manages P2P-received files. They are saved in the shared folder `Download/SrvFiles` (`DownloadDirService`), together with downloads and server-mode files. On iOS it uses the app's Documents directory.

> **Carpeta compartida.** Descargas, archivos recibidos y modo servidor usan una sola carpeta: `Download/SrvFiles`, la misma que el servidor web y la app de escritorio. Sin permisos especiales: desde Android 11 la app ve ahí solo los archivos que creó ella; lo copiado a mano con otra app o lo que quede de una instalación anterior no aparece.

## Exports / Public API

### `ReceivedFilesService`

**Constructor:** `ReceivedFilesService([Directory? dir])` — optional directory injection for testing.

| Method | Return | Description |
|---|---|---|
| `Future<Directory> getDirectory()` | `Directory` | Returns (and caches in `_dir`) the received-files directory, creating it if necessary. Android: `/storage/emulated/0/Download/SrvFiles` (falls back to `Documents/SrvFiles` if it can't write there). iOS: `<Documents>/SrvFiles`. |
| `Future<List<FileInfo>> listFiles()` | `List<FileInfo>` | Lists files sorted by modification date descending. Returns `[]` if the directory doesn't exist. `downloadUrl` is set to the absolute file path (suitable for `OpenFilex.open`). |
| `Future<String> saveFile(String fileName, List<int> bytes)` | `String` | Saves bytes to the received directory. Appends ` (1)`, ` (2)`, etc. to resolve name conflicts. Returns the absolute path of the saved file. |
| `Future<void> deleteFile(String fileName)` | `void` | Deletes the file if it exists; no-op otherwise. |

## Key behaviors

- **Directory**: the shared `SrvFiles/` folder (`DownloadDirService.getReceivedDir()`). In the phone's own server mode the home screen hides the "received" section: the server list already shows the same folder.
- **Test injection**: the optional `Directory? dir` constructor parameter pre-populates `_dir`, bypassing platform path resolution in unit tests.
- **Conflict resolution**: appends ` (N)` before the extension — `foto.jpg` → `foto (1).jpg` → `foto (2).jpg`.
- Dependencies: `dart:io`, `path_provider`, `FileInfo`.
