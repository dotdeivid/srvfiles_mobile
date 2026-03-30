# services/preview_service.dart

**File:** `lib/services/preview_service.dart`

## Purpose

Handles opening a file preview by downloading server files to a temporary path and navigating to `PreviewScreen`. Local / already-received files are opened directly without downloading.

## Exports / Public API

### `PreviewService` (static-only utility class, private constructor)

| Method | Description |
|---|---|
| `static void setMaxPreviewMb(int mb)` | Sets the size cap for server-file previews (default 50 MB). Called by `FilesController` once the server config is loaded. |
| `static Future<void> previewServerFile({required FileInfo file, required ApiConfig config, required String? sessionToken, required BuildContext context})` | Checks if the file type is previewable (`FileTypeHelper.canPreview`), checks the size cap, shows a loading spinner, downloads the file to `<tmp>/srvfiles_preview_<name>`, then navigates to `PreviewScreen(isTempFile: true)`. Shows a snackbar on error. |
| `static Future<void> previewLocalFile({required String filePath, required String fileName, required BuildContext context})` | Opens `PreviewScreen` directly for a file already on disk (`isTempFile: false`). |

## Key behaviors

- **Temp file cleanup**: `PreviewScreen` deletes the temp file in its `dispose` when `isTempFile == true`.
- **Max size check**: if `file.size > _maxBytes` a dialog is shown instead of downloading ("Archivo muy grande — descargalo para verlo").
- **Unknown type**: if `FileTypeHelper.canPreview` returns `false`, a snackbar is shown and no navigation occurs.
- **Auth header**: uses `X-SrvFiles-Token: <sessionToken>` for authenticated server downloads.
- **Temp file naming**: `<tmpDir>/srvfiles_preview_<safeFileName>` where unsafe characters are replaced with `_`.
- **Context safety**: checks `context.mounted` before every navigation/dialog operation to avoid acting on a disposed widget tree.
- Dependencies: `http`, `path_provider`, `FileTypeHelper`, `PreviewScreen`, `AppLogger`.
