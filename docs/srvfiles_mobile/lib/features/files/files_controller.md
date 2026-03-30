# features/files/files_controller.dart

**File:** `lib/features/files/files_controller.dart`

## Purpose

`ChangeNotifier` that owns all server-file state: listing, upload staging, download, share-preparation, deletion, search filtering, and view-mode toggle. Extracted from `_HomeScreenState` to keep the screen widget focused on presentation.

## Exports / Public API

### `FilesController extends ChangeNotifier`

**Constructor:**
```dart
FilesController({FilesService? filesService, ApiConfig? apiConfig, DownloadDirService? downloadDirService})
```
All parameters are optional; the controller can be created before a server connection is established and configured later via `setService`.

**Public state:**

| Field | Description |
|---|---|
| `List<FileInfo> files` | Current file list from the server. |
| `DiskStats? stats` | Current disk usage stats. |
| `AppConfig? config` | Server config (e.g. `previewMaxFileSizeMb`). |
| `bool loading` | True while `initialLoad` is in progress. |
| `String? error` | Error message to display, or `null`. |
| `bool isGridView` | Grid vs. list display toggle. |
| `bool connectionLost` | True when `refreshData` fails but the existing file list is kept. |
| `List<File> stagedFiles` | Files selected by the user but not yet uploaded. |
| `bool uploading` | True while an upload is in progress. |
| `double uploadProgress` | Upload progress 0.0–1.0. |
| `String searchQuery` | Current search term. |
| `List<FileInfo> filteredFiles` | Computed: `files` filtered by `searchQuery` (case-insensitive). |

**Key methods:**

| Method | Description |
|---|---|
| `void setService(FilesService, ApiConfig)` | Replaces the backing service (e.g. after switching servers). |
| `Future<void> initialLoad()` | Parallel fetch of `getFiles`, `getStats`, `getConfig`. Sets `loading` and `error`. Also calls `PreviewService.setMaxPreviewMb`. |
| `Future<void> refreshData()` | Lightweight re-fetch of files and stats. Sets `connectionLost` if it fails while files are cached. |
| `Future<List<File>> pickFiles()` | Opens the platform file picker (any type, multiple selection) and appends results to `stagedFiles`. |
| `void removeStagedFile(int index)` | Removes a file from the staging list. |
| `void clearStagedFiles()` | Empties the staging list. |
| `Future<void> uploadStagedFiles()` | Uploads `stagedFiles` then calls `refreshData`. Clears staged files on success. |
| `Future<String?> download(FileInfo)` | Downloads a file and saves it to `DownloadDirService.getDownloadsDir`. Returns the local path, or `null` on error. |
| `Future<String?> prepareShare(FileInfo)` | Downloads a file to a temp directory for sharing via `share_plus`. Returns the temp path. |
| `Future<bool> deleteFile(String fileName)` | Deletes a file on the server and calls `refreshData`. Returns `false` on error. |
| `void setSearchQuery(String)` | Updates `searchQuery` and notifies listeners. |
| `void toggleGridView()` | Flips `isGridView`. |
| `static String generateTransferId()` | Generates a UUID v4 using `Random.secure()`. Also used by `TransferController`. |

## Key behaviors

- `initialLoad` uses `Future.wait` to fetch files, stats, and config in parallel.
- `connectionLost` is set (not `error`) when `refreshData` fails while `files.isNotEmpty`, so the stale list remains visible.
- Auth headers for download/share are obtained from `_filesService!.authHeaders`.
- `generateTransferId` is `static` so `TransferController` can call it without a `FilesController` instance.
- Dependencies: `FilesService`, `ApiConfig`, `DownloadDirService`, `PreviewService`, `AppLogger`, `file_picker`, `http`, `path_provider`.
