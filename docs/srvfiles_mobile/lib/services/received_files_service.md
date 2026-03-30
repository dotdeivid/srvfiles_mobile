# services/received_files_service.dart

**File:** `lib/services/received_files_service.dart`

## Purpose

Manages the local directory where P2P-received files are saved. On Android the directory is under the public Downloads folder so files are visible to other apps (gallery, file manager). On iOS it uses the app's Documents directory.

## Exports / Public API

### `ReceivedFilesService`

**Constructor:** `ReceivedFilesService([Directory? dir])` — optional directory injection for testing.

| Method | Return | Description |
|---|---|---|
| `Future<Directory> getDirectory()` | `Directory` | Returns (and caches in `_dir`) the received-files directory, creating it if necessary. Android: `/storage/emulated/0/Download/SrvFiles/received` (falls back to `Documents/SrvFiles/received` if the public dir doesn't exist). iOS: `<Documents>/SrvFiles/received`. |
| `Future<List<FileInfo>> listFiles()` | `List<FileInfo>` | Lists files sorted by modification date descending. Returns `[]` if the directory doesn't exist. `downloadUrl` is set to the absolute file path (suitable for `OpenFilex.open`). |
| `Future<String> saveFile(String fileName, List<int> bytes)` | `String` | Saves bytes to the received directory. Appends ` (1)`, ` (2)`, etc. to resolve name conflicts. Returns the absolute path of the saved file. |
| `Future<void> deleteFile(String fileName)` | `void` | Deletes the file if it exists; no-op otherwise. |

## Key behaviors

- **Directory**: `SrvFiles/received/` — note this differs from `DownloadDirService.getReceivedDir()` which uses `SrvFiles/Recibidos/`. `ReceivedFilesService` is used directly by `TransferController`; `DownloadDirService` is used by `FilesController` for server-downloaded files.
- **Test injection**: the optional `Directory? dir` constructor parameter pre-populates `_dir`, bypassing platform path resolution in unit tests.
- **Conflict resolution**: appends ` (N)` before the extension — `foto.jpg` → `foto (1).jpg` → `foto (2).jpg`.
- Dependencies: `dart:io`, `path_provider`, `FileInfo`.
