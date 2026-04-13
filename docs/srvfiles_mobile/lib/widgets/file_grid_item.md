# widgets/file_grid_item.dart

**Archivo:** `lib/widgets/file_grid_item.dart`
**Rol:** Tarjeta de archivo en modo grid. Muestra emoji grande, nombre y tamaño. Long-press abre menú contextual con acciones.

---

## Props

```dart
class FileGridItem extends StatelessWidget {
  final FileInfo file;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback? onCopyLink;  // opcional
}
```

`VoidCallback` es un typedef de Dart para `void Function()`. Es el equivalente de `() => void` en TypeScript.

---

## Método `_showContextMenu`

```dart
void _showContextMenu(BuildContext context) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgSecondary,
    shape: ...,
    builder: (ctx) => SafeArea(child: Column(
      children: [
        // Handle visual
        // Header con nombre y tamaño
        ListTile('Descargar', ...),
        ListTile('Compartir', ...),
        if (onCopyLink != null) ListTile('Copiar enlace', ...),
      ],
    )),
  );
}
```

### `HapticFeedback.mediumImpact()`

Dispara una vibración táctil media. En iOS usa el Taptic Engine; en Android el vibrador. Provee feedback físico al interactuar con el long-press.

### `showModalBottomSheet`

Un panel que aparece desde la parte inferior de la pantalla con animación. El `SafeArea` dentro del builder protege el contenido de la franja del home indicator de iOS.

---

## Build

```dart
RepaintBoundary(
  child: Semantics(
    label: '...',
    child: GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: GlassCard(
        padding: ...,
        child: Column(
          children: [
            Text(getFileIcon(file.name), style: TextStyle(fontSize: 36)),
            Text(file.name, overflow: TextOverflow.ellipsis, maxLines: 2),
            Text(formatBytes(file.size)),
            const Spacer(),
            Row(children: [
              IconButton(onPressed: onDownload, ...),
              IconButton(onPressed: onShare, ...),
            ]),
          ],
        ),
      ),
    ),
  ),
)
```

El `RepaintBoundary` como raíz aísla la capa de repintado de cada tarjeta del resto de la grilla — animaciones o actualizaciones de estado en una tarjeta no invalidan las adyacentes.

`GestureDetector` intercepta gestos que el widget hijo no maneja por defecto. `onLongPress` es el gesto de mantener presionado (~500ms).

`const Spacer()` empuja los botones de acción al final del `Column`. Es el equivalente de `margin-top: auto` en CSS flexbox.

---

## `Semantics`

```dart
Semantics(
  label: '${file.name}, ${formatBytes(file.size)}',
  child: GestureDetector(...),
)
```

Envuelve el widget con metadatos para lectores de pantalla (accesibilidad). El label describe lo que el lector de pantalla anunciará cuando el usuario enfoque este elemento.
