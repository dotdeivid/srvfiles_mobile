# widgets/pin_entry_dialog.dart

**File:** `lib/widgets/pin_entry_dialog.dart`

## Purpose

Modal dialog for entering a 6-digit PIN to connect to a PIN-protected SrvFiles server. Supports both simple PIN return and inline validation (the dialog stays open on wrong PIN without keyboard flicker).

## Exports / Public API

### `PinEntryDialog extends StatefulWidget`

**Constructor parameters:**

| Parameter | Type | Description |
|---|---|---|
| `error` | `String?` | Pre-populated error message shown below the input on open. |
| `onValidate` | `Future<String?> Function(String pin)?` | If provided, called with the PIN when "Conectar" is tapped. Return `null` for success (dialog closes), or an error string to display inline (dialog stays open). |

**Static method:**

```dart
static Future<String?> show(BuildContext context, {String? error, Future<String?> Function(String pin)? onValidate})
```

Returns the PIN string if the user confirmed, or `null` if cancelled. `barrierDismissible: false` — the user must make an explicit choice.

## Key behaviors

- **Input constraints**: `FilteringTextInputFormatter.digitsOnly` + `LengthLimitingTextInputFormatter(6)` — only digits, max 6 characters.
- **"Conectar" button**: enabled only when `text.length == 6 && !_submitting` (via `ValueListenableBuilder`).
- **Inline validation**: when `onValidate` is provided, `_submit` calls it asynchronously and shows a `CircularProgressIndicator` in the button while waiting (`_submitting = true`). On success, pops with the PIN; on failure, shows the returned error string without closing the dialog.
- **Error clearing**: the error message is cleared as soon as the user types a new character (`onChanged`).
- **Cancel while submitting**: the cancel button is disabled while `_submitting` is `true`.
- **Keyboard submission**: the text field's `onSubmitted` calls `_submit` so users can confirm with the Enter key.
- Styling: monospaced 24 pt with 8 pt letter-spacing; `accentPrimary` focus border and button color.
