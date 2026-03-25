# widgets/name_dialog.dart

**Archivo:** `lib/widgets/name_dialog.dart`
**Rol:** Diálogo para configurar el nombre del dispositivo en el primer lanzamiento. Retorna el nombre elegido, o `null` si se omite.

---

## Método estático `show`

```dart
static Future<String?> show(BuildContext context, String defaultName) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NameDialog(defaultName: defaultName),
  );
}
```

Patrón idéntico a `IncomingTransferDialog.show`. El método estático encapsula la lógica de mostrar el diálogo para que el llamador solo necesite hacer:

```dart
final name = await NameDialog.show(context, defaultName);
```

---

## Estado

```dart
class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _controller;
}
```

`TextEditingController` controla el contenido y la selección del `TextField`. Debe ser creado en `initState` y destruido en `dispose` para no generar memory leaks.

`late final` indica que la variable se inicializará después de la declaración (en `initState`) pero solo una vez. El compilador verifica que esté inicializada antes de ser usada.

---

## Seleccionar todo el texto al abrir

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: _controller.text.length,
  );
});
```

`addPostFrameCallback` ejecuta el callback después del primer frame. No se puede modificar la selección durante `initState` porque el `TextField` todavía no se renderizó.

`TextSelection` con `baseOffset: 0` y `extentOffset: length` selecciona todo el texto, igual que `inputRef.current.select()` en React.

---

## Método `_save`

```dart
void _save() {
  Navigator.of(context).pop(_controller.text);
}
```

Cierra el diálogo retornando el texto del campo. El llamador (`SplashScreen`) recibe este valor como el resultado del `Future<String?>`.

Si el usuario presiona "Omitir":
```dart
Navigator.of(context).pop(null),
```

El `Future` resuelve con `null`, y `SplashScreen` usa el nombre aleatorio por defecto.
