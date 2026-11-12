# utils/file_icons.dart

**Archivo:** `lib/utils/file_icons.dart`
**Rol:** Mapea extensiones de archivo a emojis representativos. Replica `getFileIcon()` del frontend web.

---

## Mapa `_fileIcons`

```dart
const _fileIcons = {
  // Documents & text
  'doc': '📝', 'txt': '📝', 'md': '📝', 'markdown': '📝', 'log': '📝', /* … */
  // PDF
  'pdf': '📄',
  // Images, Video, Audio, Archives, Apps & installers, Code, Web & data,
  // Spreadsheets & presentations…
};
```

Grupos: texto (📝, incluye Markdown), PDF (📄), imágenes (🖼️), video (🎬), audio (🎵), comprimidos (📦), apps e instaladores (💿, incluye `.apk`), código (⚙️), web y datos (🌐), hojas de cálculo y presentaciones (📊). Es idéntico a `frontend/src/shared/utils/fileIcons.ts` de la web: si se cambia uno, cambiar el otro.

Un `Map` constante de extensión → emoji. Al ser `const`, se evalúa en tiempo de compilación y no genera ningún overhead en runtime.

---

## Función `getFileIcon`

```dart
String getFileIcon(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == filename.length - 1) return _defaultIcon;
  final ext = filename.substring(dotIndex + 1).toLowerCase();
  return _fileIcons[ext] ?? _defaultIcon;
}
```

### `lastIndexOf('.')`

Encuentra la posición del último punto del nombre. Se usa `lastIndexOf` (no `indexOf`) para manejar nombres como `archivo.tar.gz` correctamente — la extensión es `gz`, no `tar.gz`.

Si no hay punto (o el nombre termina en punto), retorna el ícono genérico de documento `📃`. Antes era `📁`, que se confundía con una carpeta.

### `substring(dotIndex + 1)`

Extrae la extensión: si `filename = "foto.JPG"` y `dotIndex = 4`, entonces `substring(5) = "JPG"`. `.toLowerCase()` normaliza a minúsculas para que `JPG`, `jpg`, `Jpg` den el mismo resultado.

### `?? _defaultIcon`

Si la extensión no está en el mapa (ej: `.xyz`), el operador null-coalescing retorna el ícono genérico de documento (`📃`).
