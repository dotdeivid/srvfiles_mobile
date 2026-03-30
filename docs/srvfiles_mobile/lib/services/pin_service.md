# services/pin_service.dart

**File:** `lib/services/pin_service.dart`

## Purpose

Manages the security PIN for server mode. The PIN is generated automatically when the embedded relay activates server mode and is stored as a SHA-256 hash in `SharedPreferences`. The plain-text PIN is returned once so the UI can display it, but only the hash is persisted.

## Exports / Public API

### `PinService`

| Method | Description |
|---|---|
| `Future<String> generatePin()` | Generates a cryptographically random 6-digit PIN (100000–999999 via `Random.secure()`), stores its SHA-256 hash under key `'security_pin_hash'`, and returns the plain-text PIN. Logs success or rethrows on failure. |
| `Future<bool> validatePin(String input)` | Hashes `input` with SHA-256 and compares to the stored hash. Returns `false` if no hash is stored or the PIN is wrong. Logs wrong-PIN attempts as warnings. |
| `Future<void> clearPin()` | Removes the stored hash from `SharedPreferences` (called when server mode is deactivated). |

## Key behaviors

- Storage key: `'security_pin_hash'` in `SharedPreferences`.
- Hashing algorithm: SHA-256 via the `crypto` package (`sha256.convert(utf8.encode(pin))`).
- Plain-text PIN is never stored — only the hash survives process restarts.
- All public methods log to `AppLogger.instance` (info on success, warn on bad PIN, error on exception).
- Dependencies: `crypto`, `shared_preferences`, `app_logger.dart`.
