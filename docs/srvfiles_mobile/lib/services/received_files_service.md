# services/received_files_service.dart

**Archivo:** `lib/services/received_files_service.dart`
**Rol:** Gestiona el directorio local donde se guardan los archivos recibidos por transferencia P2P. Maneja conflictos de nombres, listado y eliminación.

---

## Función `getDirectory`

```dart
Future<Directory> getDirectory() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/SrvFilesReceived');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
```

Obtiene o crea el directorio `SrvFilesReceived` dentro del directorio de documentos de la app. `getApplicationDocumentsDirectory()` retorna un directorio diferente en cada plataforma:
- Android: `/data/user/0/com.dotdeivid.srvfiles/app_flutter/`
- iOS: `Documents/` del sandbox de la app

El directorio es persistente (no se borra al cerrar la app) y es privado a la app.

---

## Función `listFiles`

```dart
Future<List<FileInfo>> listFiles() async {
  final dir = await getDirectory();
  final entities = await dir.list().toList();
  return entities
      .whereType<File>()
      .map((f) {
        final name = f.path.split('/').last;
        final stat = f.statSync();
        return FileInfo(
          name: name,
          size: stat.size,
          createdAt: stat.modified.toIso8601String(),
          downloadUrl: f.path,
        );
      })
      .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
```

Lista los archivos del directorio. `dir.list()` retorna un `Stream<FileSystemEntity>` (puede incluir subdirectorios); `.whereType<File>()` filtra solo los archivos. El `downloadUrl` es la ruta absoluta en el sistema de archivos, que `OpenFilex` puede abrir directamente.

---

## Función `saveFile`

```dart
Future<String> saveFile(String fileName, Uint8List bytes) async {
  final dir = await getDirectory();
  final file = await _resolveConflict(dir, fileName);
  await file.writeAsBytes(bytes);
  return file.path;
}
```

Guarda los bytes del archivo recibido. Retorna la ruta donde se guardó (usada para mostrar el SnackBar con "Abrir").

---

## Función `_resolveConflict`

```dart
Future<File> _resolveConflict(Directory dir, String fileName) async {
  final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
  final base = ext.isNotEmpty
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;

  File candidate = File('${dir.path}/$fileName');
  int counter = 1;
  while (await candidate.exists()) {
    candidate = File('${dir.path}/$base ($counter)$ext');
    counter++;
  }
  return candidate;
}
```

Si ya existe un archivo con el mismo nombre, genera un nombre alternativo: `foto.jpg` → `foto (1).jpg` → `foto (2).jpg`, etc. El mismo patrón que usa Windows para resolver conflictos de nombres.

---

## Función `deleteFile`

```dart
Future<void> deleteFile(String fileName) async {
  final dir = await getDirectory();
  final file = File('${dir.path}/$fileName');
  if (await file.exists()) {
    await file.delete();
  }
}
```

Elimina un archivo del directorio de recibidos. La guarda `if (await file.exists())` evita una excepción si el archivo ya fue borrado por otro medio.
