# utils/file_type_helper.dart

**File:** `lib/utils/file_type_helper.dart`

## Purpose

Classifies files by extension into a `FileCategory` enum. Used by `PreviewService` to decide whether a file can be previewed inline, and by `PreviewScreen` to select the appropriate viewer widget.

## Exports / Public API

### `FileCategory` (enum)

| Value | Extensions |
|---|---|
| `image` | jpg, jpeg, png, gif, webp, bmp, ico |
| `svg` | svg |
| `video` | mp4, mov, m4v, webm |
| `audio` | mp3, wav, aac, m4a, ogg, flac, opus |
| `pdf` | pdf |
| `text` | txt, md, json, xml, csv, yaml, yml, html, htm, js, jsx, ts, tsx, dart, py, go, rs, swift, kt, java, c, cpp, h, css, sh, bash, zsh |
| `unknown` | anything else |

### `FileTypeHelper` (static-only utility class, private constructor)

| Method | Description |
|---|---|
| `static FileCategory categorize(String fileName)` | Extracts the lowercase extension from `fileName` and returns the matching `FileCategory`, or `FileCategory.unknown`. |
| `static bool canPreview(String fileName)` | Returns `true` if `categorize` returns anything other than `FileCategory.unknown`. Used as a gate in `PreviewService`. |

## Key behaviors

- Extension extraction: finds the last `.` in the filename; if none (or trailing `.`), returns `''` which maps to `unknown`.
- Extension matching is case-insensitive (lowercased before lookup).
- No external dependencies.
