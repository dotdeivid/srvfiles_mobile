# services/app_logger.dart

**File:** `lib/services/app_logger.dart`

## Purpose

Centralised logger for the SrvFiles mobile app. Wraps the `logger` package behind a singleton (`AppLogger.instance`) with four severity levels. In release builds only `warn` and `error` entries are written to a persistent file; in debug builds `ConsoleOutput` is added so all levels appear in the terminal.

## Exports / Public API

### `AppLogger` (singleton class)

| Member | Description |
|---|---|
| `static final instance` | The single shared instance. |
| `Future<void> init()` | Must be called once in `main()` before `runApp`. Resolves the log directory (`Documents/SrvFiles/logs/errors.txt`), creates it if needed, and constructs the `Logger`. |
| `void error(String msg, {Object? error, StackTrace? stack})` | Logs at `Level.error`. Always written to file and console (debug). |
| `void warn(String msg)` | Logs at `Level.warning`. Written to file. |
| `void info(String msg)` | Logs at `Level.info`. Console only in debug. |
| `void debug(String msg)` | Logs at `Level.debug`. Console only in debug. |

### `_FileOutput` (private)

Internal `LogOutput` subclass that appends a single line per event to the log file, but **only for `Level.warning` and above** (checked via `event.level.index < Level.warning.index`). Each entry is flushed immediately (`flush: true`) to prevent loss on crash.

## Key behaviors

- **`ProductionFilter`** is used as the filter, meaning all levels are forwarded to the output chain; the file-output guard is the sole filter for file writes.
- Log file path: `<Documents>/SrvFiles/logs/errors.txt`. The directory is created with `recursive: true` during `init()`.
- `SimplePrinter(printTime: true, colors: false)` formats entries as plain text with a timestamp — suitable for attaching to bug reports.
- `init()` is `async` and awaited in `main()` before `runApp`, ensuring the logger is ready before any service emits log entries.
- Dependencies: `logger` package, `path_provider`.
