# widgets/file_list_item.dart

**Archivo:** `lib/widgets/file_list_item.dart`
**Rol:** Fila de archivo en modo lista. Muestra emoji, nombre, tamaño, y botones de acción. Long-press abre menú contextual. Permite personalizar el ícono y tooltip del botón principal.

---

## Props

```dart
class FileListItem extends StatelessWidget {
  final FileInfo file;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback? onCopyLink;   // opcional
  final VoidCallback? onDelete;     // opcional (archivos recibidos)
  final IconData downloadIcon;      // default: Icons.download_rounded
  final String downloadTooltip;     // default: 'Descargar'
}
```

Los parámetros opcionales con defaults permiten reusar este widget para dos propósitos:
1. **Archivos del servidor**: `onDownload` descarga el archivo, ícono de descarga.
2. **Archivos recibidos**: `onDownload` llama `OpenFilex.open`, ícono de ojo (`remove_red_eye`), tooltip "Abrir".

---

## Clase `_ContextMenuItem`

```dart
class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;  // si es true, color rojo
}
```

Widget privado auxiliar para las filas del menú contextual. El parámetro `destructive: true` cambia el color del ícono y el texto a `AppColors.danger`, señalando visualmente que la acción es irreversible (como "Eliminar").

---

## `InkWell` vs `GestureDetector`

```dart
InkWell(
  onLongPress: () => _showContextMenu(context),
  child: Container(...),
)
```

`InkWell` es como `GestureDetector` pero con el efecto de "onda" (ripple) de Material Design al tocar. Para filas de lista, `InkWell` es preferido porque provee feedback visual táctil consistente.

---

## Estructura visual

```
RepaintBoundary
└── Semantics
    └── InkWell
        └── Container
            └── Row
                ├── Text(emoji)              22px
                ├── Column (Expanded)
                │   ├── Text(nombre)         14px, negrita, elipsis
                │   └── Text(tamaño)         12px, muted
                ├── IconButton(descargar)
                └── IconButton(compartir)
```

`Expanded` hace que la columna de texto tome todo el espacio horizontal disponible, empujando los botones al extremo derecho. Sin `Expanded`, el `Row` no sabría cómo distribuir el espacio.

`RepaintBoundary` aísla la capa de repintado de este widget del resto del árbol. Cuando un item adyacente en la lista cambia de estado (p.ej. progreso de descarga), Flutter puede redibujar solo ese item sin invalidar toda la lista. Especialmente importante en listas largas con múltiples ítems actualizándose en paralelo.
