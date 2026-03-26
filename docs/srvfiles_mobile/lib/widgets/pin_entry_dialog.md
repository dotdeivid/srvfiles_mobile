# widgets/pin_entry_dialog.dart

**Archivo:** `lib/widgets/pin_entry_dialog.dart`
**Rol:** Diálogo modal para ingresar el PIN de un servidor protegido. Se muestra cuando el mobile intenta conectarse a un servidor externo que requiere autenticación.

---

## API pública

```dart
static Future<String?> show(BuildContext context, {String? error}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PinEntryDialog(error: error),
  );
}
```

Método estático de conveniencia. Retorna el PIN ingresado o `null` si el usuario canceló. `barrierDismissible: false` obliga al usuario a tomar una decisión explícita (no puede cerrar tocando fuera).

---

## Estado interno

```dart
final _controller = TextEditingController();
String? _error;
```

- `_controller`: texto del input del PIN.
- `_error`: mensaje de error a mostrar (puede venir del exterior al llamar `show(error: ...)` o del propio widget al validar).

---

## Validación

```dart
void _submit() {
  final pin = _controller.text.trim();
  if (pin.length != 6) {
    setState(() => _error = 'El PIN debe tener 6 dígitos');
    return;
  }
  Navigator.of(context).pop(pin);
}
```

Solo acepta exactamente 6 dígitos. El input ya está limitado por `LengthLimitingTextInputFormatter(6)` y `FilteringTextInputFormatter.digitsOnly`.

---

## Botón "Conectar"

```dart
ValueListenableBuilder<TextEditingValue>(
  valueListenable: _controller,
  builder: (_, value, _) {
    return FilledButton(
      onPressed: value.text.length == 6 ? _submit : null,
      child: const Text('Conectar'),
    );
  },
),
```

`ValueListenableBuilder` escucha los cambios del `TextEditingController` y habilita el botón solo cuando hay exactamente 6 dígitos, sin necesidad de `setState`.

---

## Cancelar

```dart
TextButton(
  onPressed: () => Navigator.of(context).pop(null),
  child: const Text('Cancelar'),
),
```

Retorna `null` al caller. `HomeScreen._showPinEntryDialog` lo detecta y navega de vuelta al splash:

```dart
if (pin == null) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const SplashScreen()),
  );
  return;
}
```
