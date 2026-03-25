# widgets/incoming_transfer_dialog.dart

**Archivo:** `lib/widgets/incoming_transfer_dialog.dart`
**Rol:** Diálogo modal que aparece cuando otro dispositivo quiere enviar un archivo. Muestra remitente, nombre y tamaño del archivo. Retorna `true` si se acepta, `false` si se rechaza.

---

## Método estático `show`

```dart
static Future<bool?> show(
  BuildContext context,
  IncomingTransferRequest request,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => IncomingTransferDialog(
      request: request,
      onAccept: () => Navigator.of(ctx).pop(true),
      onReject: () => Navigator.of(ctx).pop(false),
    ),
  );
}
```

### `barrierDismissible: false`

Evita que el usuario cierre el diálogo tocando fuera de él. En una solicitud de transferencia, el usuario debe tomar una decisión explícita; cerrar el diálogo accidentalmente causaría que la transferencia quede en un estado indefinido.

### `Navigator.of(ctx).pop(value)`

`pop` cierra el diálogo y retorna el valor al llamador. `showDialog<bool>` retorna un `Future<bool?>` que se resuelve con ese valor.

En `HomeScreen`:
```dart
final accepted = await IncomingTransferDialog.show(context, request);
if (accepted == true) {
  _acceptTransfer(request);
} else {
  _transferService.reject(request.transferId);
}
```

---

## Build

El diálogo muestra:
1. **Título**: "Archivo entrante" con ícono de descarga.
2. **Remitente**: nombre del dispositivo que envía.
3. **Archivo**: emoji del tipo de archivo, nombre (con elipsis), tamaño formateado.
4. **Pregunta**: "¿Querés recibir este archivo?"
5. **Botones**: "Rechazar" (TextButton) y "Aceptar" (ElevatedButton).

---

## Accesibilidad

```dart
Semantics(
  button: true,
  label: 'Aceptar transferencia',
  child: ElevatedButton(...),
),
```

`Semantics(button: true)` le indica al sistema de accesibilidad que este widget es un botón interactivo. El `label` es lo que el lector de pantalla anuncia al usuario.
