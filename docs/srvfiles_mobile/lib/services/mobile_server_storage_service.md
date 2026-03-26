# services/mobile_server_storage_service.dart

**Archivo:** `lib/services/mobile_server_storage_service.dart`
**Rol:** Gestiona los archivos del servidor local cuando el mobile está en server mode. Los archivos se almacenan en `Documents/SrvFiles/server/`, separados de los archivos recibidos por P2P.

---

## Directorio de almacenamiento

```dart
Future<Directory> getDirectory() async {
  if (_dir != null) return _dir!;
  final baseDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${baseDir.path}/SrvFiles/server');
  if (!await dir.exists()) await dir.create(recursive: true);
  _dir = dir;
  return dir;
}
```

Crea el directorio `Documents/SrvFiles/server/` si no existe. El resultado se cachea en `_dir` para no repetir la resolución en cada llamada.

---

## Método `listFiles`

```dart
Future<List<FileInfo>> listFiles() async {
  final dir = await getDirectory();
  final entities = dir.listSync().whereType<File>().toList();
  entities.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return entities.map((file) => FileInfo(
    name: file.path.split('/').last,
    size: file.statSync().size,
    createdAt: file.statSync().modified.toIso8601String(),
    downloadUrl: '/api/files/download/${Uri.encodeComponent(name)}',
  )).toList();
}
```

Lista los archivos ordenados por fecha de modificación (más reciente primero). La URL de descarga es relativa, compatible con el relay embebido.

---

## Método `saveFile`

```dart
Future<String> saveFile(String fileName, List<int> bytes) async {
  final dir = await getDirectory();
  final sanitized = _sanitize(fileName);
  var target = File('${dir.path}/$sanitized');

  if (await target.exists()) {
    // Generar nombre único: "archivo (1).ext", "archivo (2).ext", ...
    var i = 1;
    while (await target.exists()) {
      target = File('${dir.path}/$base ($i)$ext');
      i++;
    }
  }

  await target.writeAsBytes(bytes);
  return target.path.split('/').last;
}
```

Resuelve conflictos de nombre automáticamente. Si `foto.jpg` ya existe, guarda `foto (1).jpg`, etc.

---

## Método `getStats`

```dart
Future<DiskStats> getStats() async {
  final dir = await getDirectory();
  int used = 0;
  for (final entity in dir.listSync().whereType<File>()) {
    used += entity.statSync().size;
  }

  int total = 0, free = 0;
  try {
    final freeMb  = await _diskChannel.invokeMethod<double>('getFreeDiskSpace');
    final totalMb = await _diskChannel.invokeMethod<double>('getTotalDiskSpace');
    free  = ((freeMb  ?? 0) * 1024 * 1024).round();
    total = ((totalMb ?? 0) * 1024 * 1024).round();
  } catch (_) {}

  return DiskStats(total: total, used: used, free: free);
}
```

- `used`: suma del tamaño de los archivos en `Documents/SrvFiles/server/`.
- `total` / `free`: obtenidos vía un `MethodChannel` que llama a `StatFs` en Android (`MainActivity.kt`). Esto evita depender de paquetes externos incompatibles con el Android Gradle Plugin moderno.

### ¿Por qué MethodChannel y no un paquete?

El paquete `disk_space` no era compatible con el AGP moderno (faltaba declaración de namespace en `build.gradle`). La alternativa es implementar el canal nativo directamente en `MainActivity.kt`:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.srvfiles/disk_space")
  .setMethodCallHandler { call, result ->
    when (call.method) {
      "getFreeDiskSpace"  -> result.success(StatFs(filesDir.absolutePath).availableBlocksLong * blockSize / MB)
      "getTotalDiskSpace" -> result.success(StatFs(filesDir.absolutePath).blockCountLong * blockSize / MB)
      else -> result.notImplemented()
    }
  }
```

---

## Método `_sanitize`

```dart
String _sanitize(String name) {
  var result = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  result = result.replaceAll(RegExp(r'\.{2,}'), '_');
  return result.trim().isEmpty ? 'archivo' : result.trim();
}
```

Elimina caracteres que no son válidos en nombres de archivo y previene path traversal (`..`).
