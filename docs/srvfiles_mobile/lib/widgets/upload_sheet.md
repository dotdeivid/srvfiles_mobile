# widgets/upload_sheet.dart

**Archivo:** `lib/widgets/upload_sheet.dart`
**Rol:** BottomSheet de staging para subir archivos. Muestra los archivos seleccionados, permite remover individuales o limpiar todos, y sube con barra de progreso.

---

## Props

```dart
class UploadSheet extends StatelessWidget {
  final List<File> files;
  final bool uploading;
  final double uploadProgress;   // 0.0 a 1.0
  final void Function(int index) onRemove;
  final VoidCallback onClearAll;
  final VoidCallback onUpload;
  final int? maxFileSizeMb;      // null = sin límite
}
```

Es un `StatelessWidget` porque todo el estado está en `HomeScreen`. El sheet solo renderiza lo que recibe. Cuando el usuario interactúa (remover, subir), invoca los callbacks que modifican el estado del padre.

---

## Tamaño total

```dart
final totalSize = files.fold<int>(0, (sum, f) => sum + f.lengthSync());
```

`fold` es el equivalente de `reduce` en JavaScript. Parte de `0` y acumula el tamaño de cada archivo. `f.lengthSync()` lee el tamaño del archivo del sistema de archivos de forma sincrónica.

---

## Validación de límite de tamaño

```dart
final overLimit = maxFileSizeMb != null &&
    size > maxFileSizeMb! * 1024 * 1024;
```

Si `maxFileSizeMb` está definido (viene del servidor vía `AppConfig`), compara el tamaño del archivo en bytes con el límite en bytes. Si supera el límite, el nombre del archivo se muestra en rojo y el tamaño indica "— excede el límite".

---

## `ConstrainedBox`

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxHeight: 200),
  child: ListView.builder(...),
),
```

Limita la altura máxima de la lista de archivos a 200 píxeles. Sin esto, si el usuario selecciona muchos archivos, la lista crecería indefinidamente y podría salir de la pantalla.

---

## Barra de progreso durante upload

```dart
if (uploading) ...[
  FractionallySizedBox(
    widthFactor: uploadProgress.clamp(0.0, 1.0),
    child: Container(decoration: BoxDecoration(gradient: AppColors.accentGradient)),
  ),
  Text('${(uploadProgress * 100).round()}%'),
],
```

`FractionallySizedBox` (sin animación, a diferencia de `AnimatedFractionallySizedBox`) muestra el progreso actual directamente. No necesita animación porque el progreso se actualiza frecuentemente y la animación haría que "persiguiera" el valor real.

---

## Botón de upload

```dart
ElevatedButton.icon(
  label: Text(
    'Subir ${files.length > 1 ? '${files.length} archivos' : 'archivo'}'
    ' (${formatBytes(totalSize)})',
  ),
)
```

Pluraliza automáticamente: "Subir archivo (1.2 MB)" o "Subir 3 archivos (4.5 MB)". Esta concatenación de strings en tiempo de build es el equivalente de template literals en JavaScript.
