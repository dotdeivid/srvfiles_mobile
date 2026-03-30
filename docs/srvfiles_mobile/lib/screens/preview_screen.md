# screens/preview_screen.dart

**File:** `lib/screens/preview_screen.dart`

## Purpose

Full-screen file preview. Selects the correct viewer widget based on the file's `FileCategory` (image, SVG, video, audio, PDF, text, or unknown). When opened for a temporary file (e.g. a server file downloaded just for preview), the temp file is deleted on dispose.

## Exports / Public API

### `PreviewScreen extends StatefulWidget`

**Constructor parameters:**

| Parameter | Type | Description |
|---|---|---|
| `filePath` | `String` | Absolute path to the file on disk. |
| `fileName` | `String` | Display name shown in the app bar. |
| `isTempFile` | `bool` | If `true`, the file at `filePath` is deleted when the screen is disposed (default `false`). |

## Viewer widgets (private)

| Widget | Category | Package |
|---|---|---|
| `_ImagePreview` | `image` | `photo_view` — pinch/zoom with `PhotoView`. |
| `_SvgPreview` | `svg` | `flutter_svg` — `SvgPicture.file`. |
| `_VideoPreview` | `video` | `video_player` + `chewie` — auto-initialises controller. |
| `_AudioPreview` | `audio` | `audioplayers` — play/pause with seek slider and time display. |
| `_PdfPreview` | `pdf` | `pdfx` — `PdfController` + `PdfView` with vertical scroll. |
| `_TextPreview` | `text` | Flutter `Text` widget — reads file as UTF-8, displays monospaced in a `SingleChildScrollView`. |
| `_UnknownPreview` | `unknown` | Falls back to `OpenFilex.open(filePath)` via an "Abrir con…" button. |

## Key behaviors

- **Temp file cleanup**: `_PreviewScreenState.dispose` checks `isTempFile`; if `true`, calls `file.exists()` then `file.delete()` asynchronously.
- **App bar**: black semi-transparent, shows `fileName` with ellipsis overflow.
- **Back FAB**: floating action button in the bottom-left for easy one-handed navigation back.
- **Video**: `ChewieController` is created only after `VideoPlayerController.initialize()` completes to avoid showing an empty player.
- **Audio**: listens to `AudioPlayer` streams for state, position, and duration updates; only shows the seek slider after duration is known.
- **Text**: reads the file asynchronously in `initState`; shows a spinner while loading, or an error message if `readAsString` throws.
- Dependencies: `photo_view`, `flutter_svg`, `video_player`, `chewie`, `audioplayers`, `pdfx`, `open_filex`, `FileTypeHelper`, `AppColors`.
