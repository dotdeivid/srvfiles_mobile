# services/device_name_service.dart

**File:** `lib/services/device_name_service.dart`

## Purpose

Manages the device display name used for P2P identification, with persistence in `SharedPreferences`. Generates a random adjective + animal name on first launch. Mirrors the pattern of `useDeviceName.ts` in the frontend.

## Exports / Public API

### `DeviceNameService`

| Method | Return | Description |
|---|---|---|
| `Future<String> getName()` | `String` | Returns the stored name, or a random name if none is saved. On error, logs via `AppLogger` and returns a random name. |
| `Future<String> saveName(String name)` | `String` | Trims the input; if empty, generates a random name instead. Persists under key `'srvfiles-device-name'`. Returns the final saved name. |
| `Future<bool> isFirstLaunch()` | `bool` | `true` if the storage key `'srvfiles-device-name'` does not exist in `SharedPreferences` (uses `containsKey`). |
| `String generateRandomName()` | `String` | Generates a random name without saving (public wrapper around the private `_randomName`). |

## Key behaviors

- **Storage key**: `'srvfiles-device-name'` (in `SharedPreferences`).
- **Name format**: `"<adjective> <animal>"` — same vocabulary as the web frontend (`useDeviceName.ts`). Adjectives: Rápido, Azul, Verde, Veloz, Brillante, Tranquilo, Creativo, Curioso. Animals: Zorro, Puma, Delfín, Águila, Jaguar, Lobo, Oso, Cóndor.
- **`saveName` empty guard**: if the trimmed input is empty, a random name is generated and saved instead of storing an empty string.
- **`isFirstLaunch`** uses `prefs.containsKey(_storageKey)` — more reliable than a null check since `SharedPreferences` distinguishes missing keys from null values.
- All methods log activity at the appropriate level via `AppLogger.instance`.
- Dependencies: `shared_preferences`, `dart:math`, `AppLogger`.
