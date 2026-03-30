# main.dart

**File:** `lib/main.dart`

## Purpose

Entry point of the SrvFiles Flutter app. Initialises global services (`AppLogger`, `NotificationService`), configures the Android/iOS system UI overlay, and mounts the root widget.

## Exports / Public API

### `main()` (async)

Execution order:
1. `WidgetsFlutterBinding.ensureInitialized()` — required before any plugin call in an async `main`.
2. `await AppLogger.instance.init()` — initialises the persistent log file at `Documents/SrvFiles/logs/errors.txt`.
3. `await NotificationService().init()` — initialises `flutter_local_notifications` and, on Android 13+, requests the notification permission.
4. `SystemChrome.setSystemUIOverlayStyle(...)` — configures:
   - `statusBarColor: Colors.transparent` — content bleeds behind the status bar.
   - `statusBarIconBrightness: Brightness.light` — white status bar icons (dark theme).
   - `systemNavigationBarColor: AppColors.bgPrimary` — navigation bar matches app background.
   - `systemNavigationBarIconBrightness: Brightness.light` — white navigation bar icons.
5. `runApp(const SrvFilesApp())`.

### `SrvFilesApp extends StatelessWidget`

Root `MaterialApp` configured with:
- `title: 'SrvFiles'`
- `debugShowCheckedModeBanner: false`
- `theme: AppTheme.dark`
- `home: const SplashScreen()` — first screen, auto-discovers and connects to a LAN server.

## Key behaviors

- `AppLogger` is initialised before `NotificationService` so that any initialisation error in the notification service can be logged.
- `SplashScreen` is the home route rather than `HomeScreen` so that server discovery happens before the main UI appears.
- Dependencies: `AppLogger`, `NotificationService`, `AppTheme`, `AppColors`, `SplashScreen`.
