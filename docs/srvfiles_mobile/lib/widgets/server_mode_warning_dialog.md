# widgets/server_mode_warning_dialog.dart

**Archivo:** `lib/widgets/server_mode_warning_dialog.dart`
**Rol:** Diálogo de advertencia que se muestra la primera vez que el usuario intenta activar el server mode. Informa sobre el consumo de batería, la exposición en la red, y la generación automática de PIN.

---

## API pública

```dart
static Future<bool?> show(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ServerModeWarningDialog(),
  );
}
```

Retorna `true` si el usuario confirmó, `null` / `false` si canceló.

---

## Checkbox "No volver a mostrar"

```dart
bool _dontShowAgain = false;

CheckboxListTile(
  value: _dontShowAgain,
  onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
  title: const Text('No volver a mostrar este aviso'),
),
```

Al confirmar con el checkbox activo, se guarda en `SharedPreferences`:

```dart
if (_dontShowAgain) {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('server_mode_warning_dismissed', true);
}
Navigator.of(context).pop(true);
```

`HomeScreen._activateServerMode` lee esta preferencia antes de mostrar el diálogo:

```dart
final dismissed = prefs.getBool('server_mode_warning_dismissed') ?? false;
if (!dismissed && mounted) {
  final confirmed = await ServerModeWarningDialog.show(context);
  if (confirmed != true) return;
}
```

**El PIN se genera siempre**, incluso cuando el diálogo no se muestra. El checkbox solo omite el diálogo, no la seguridad.

---

## Contenido del diálogo

```
⚠️  Activar modo servidor

Tené en cuenta:
• Consume batería más rápido
• El servidor se pausa si cerrás la app o apagás la pantalla
• Cualquier dispositivo en tu red podrá acceder a los archivos

🔒 Se generará un PIN automático para proteger el acceso

☐  No volver a mostrar este aviso

[Cancelar]      [Encender]
```
