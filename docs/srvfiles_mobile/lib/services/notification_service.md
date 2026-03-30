# services/notification_service.dart

**File:** `lib/services/notification_service.dart`

## Purpose

Singleton service that wraps `flutter_local_notifications`. Shows system notifications for incoming transfer requests, completed P2P transfers, and completed downloads. Also manages the Android foreground service notification that keeps the process alive in the background.

## Exports / Public API

### `NotificationService` (singleton)

| Method | Description |
|---|---|
| `Future<void> init()` | Initialises the plugin (idempotent — returns early if already initialised). Configures `@mipmap/ic_launcher` for Android and `DarwinInitializationSettings` (alerts + sound, no badge) for iOS. On Android 13+ requests the `POST_NOTIFICATIONS` permission at runtime. Logs success or error via `AppLogger`. |
| `Future<void> showDownloadComplete(String fileName)` | Notification: "Descarga completada" / `"<fileName>" se descargó correctamente`. |
| `Future<void> showTransferComplete(String fileName, String fromName)` | Notification: "Archivo recibido" / `"<fileName>" de <fromName>`. |
| `Future<void> showIncomingTransfer(String fromName, String fileName)` | Notification: `"<fromName> quiere enviarte un archivo"` / `"<fileName> — Abrí la app para aceptar o rechazar"`. |
| `Future<void> startForeground()` | Android only. Shows a persistent low-priority notification via `startForegroundService` (channel `srvfiles_bg`). Falls back to `_plugin.show` if the API is unavailable. No-op on iOS. |
| `Future<void> stopForeground()` | Android only. Calls `stopForegroundService()` and `cancel(_idForeground)`. No-op on iOS. |

## Key behaviors

- **Notification IDs**: `showDownloadComplete`, `showTransferComplete`, `showIncomingTransfer` use `DateTime.now().millisecondsSinceEpoch ~/ 1000` as the ID, so rapid successive notifications don't replace each other.
- **Foreground service ID**: constant `_idForeground = 1` (replaces the previous notification if called again).
- **Android channels**:
  - `'srvfiles_bg'` ("SrvFiles activo"): `Importance.low`, no sound, no vibration, `ongoing: true` — the foreground service notification.
  - `'srvfiles_transfers'` ("Transferencias"): `Importance.defaultImportance` — transfer/download notifications.
- **`didChangeAppLifecycleState` integration** (in `HomeScreen`): `startForeground()` is called on `AppLifecycleState.paused`; `stopForeground()` is called on `resumed` and in `dispose`. The foreground service is never active while the user is using the app.
- Dependencies: `flutter_local_notifications`, `AppLogger`, `dart:io`.
