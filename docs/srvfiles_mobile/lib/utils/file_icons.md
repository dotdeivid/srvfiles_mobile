# utils/file_icons.dart

**Archivo:** `lib/utils/file_icons.dart`
**Rol:** Mapea extensiones de archivo a emojis representativos. Replica `getFileIcon()` del frontend web.

---

## Mapa `_fileIcons`

```dart
const _fileIcons = {
  'pdf': '📄',
  'jpg': '🖼️',
  'jpeg': '🖼️',
  'png': '🖼️',
  'mp4': '🎬',
  'mp3': '🎵',
  'zip': '📦',
  // ...
};
```

Un `Map` constante de extensión → emoji. Al ser `const`, se evalúa en tiempo de compilación y no genera ningún overhead en runtime.

---

## Función `getFileIcon`

```dart
String getFileIcon(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot == -1) return '📁';
  final ext = filename.substring(dot + 1).toLowerCase();
  return _fileIcons[ext] ?? '📁';
}
```

### `lastIndexOf('.')`

Encuentra la posición del último punto del nombre. Se usa `lastIndexOf` (no `indexOf`) para manejar nombres como `archivo.tar.gz` correctamente — la extensión es `gz`, no `tar.gz`.

Si no hay punto (`dot == -1`), retorna el emoji de carpeta genérico.

### `substring(dot + 1)`

Extrae la extensión: si `filename = "foto.JPG"` y `dot = 4`, entonces `substring(5) = "JPG"`. `.toLowerCase()` normaliza a minúsculas para que `JPG`, `jpg`, `Jpg` den el mismo resultado.

### `?? '📁'`

Si la extensión no está en el mapa (ej: `.dart`, `.iso`), el operador null-coalescing retorna el emoji genérico.
