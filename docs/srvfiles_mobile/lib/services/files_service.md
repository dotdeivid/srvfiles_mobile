# services/files_service.dart

**Archivo:** `lib/services/files_service.dart`
**Rol:** Cliente HTTP para todas las operaciones de archivos contra el backend. Encapsula las llamadas de red y devuelve modelos tipados.

---

## Clase `FilesService`

```dart
class FilesService {
  FilesService(this._config);
  final ApiConfig _config;
}
```

Recibe un `ApiConfig` en el constructor, que contiene la URL base del servidor. Todos los métodos usan `_config` para construir las URLs.

---

## Método `getFiles`

```dart
Future<List<FileInfo>> getFiles() async {
  final response = await http.get(Uri.parse(_config.filesUrl));
  final json = jsonDecode(response.body);
  final list = json['files'] as List;
  return list.map((f) => FileInfo.fromJson(f)).toList();
}
```

Obtiene la lista de archivos del servidor. `json['files'] as List` es un casteo que convierte el `dynamic` a `List`, y luego `.map` convierte cada elemento en un `FileInfo` con el constructor `fromJson`.

---

## Método `uploadFile`

```dart
Future<void> uploadFile(File file) async {
  final request = http.MultipartRequest('POST', Uri.parse('${_config.filesUrl}/upload'));
  request.files.add(await http.MultipartFile.fromPath('files', file.path));
  await request.send();
}
```

### `http.MultipartRequest`

HTTP multipart/form-data es el formato estándar para subir archivos. Es diferente de un POST normal (JSON): en lugar de un cuerpo de texto, contiene "partes" separadas por un boundary, cada parte con su propio header.

`MultipartFile.fromPath` lee el archivo del sistema de archivos y lo adjunta. El nombre del campo `'files'` debe coincidir con el que espera Multer en el backend.

---

## Método `uploadFiles`

```dart
Future<void> uploadFiles(List<File> files) async {
  final request = http.MultipartRequest('POST', Uri.parse('${_config.filesUrl}/upload'));
  for (final file in files) {
    request.files.add(await http.MultipartFile.fromPath('files', file.path));
  }
  await request.send();
}
```

Variante que sube múltiples archivos en un solo request multipart. El backend recibe todos los archivos en `req.files`.

---

## Método `deleteFile`

```dart
Future<void> deleteFile(String filename) async {
  await http.delete(
    Uri.parse('${_config.filesUrl}/${Uri.encodeComponent(filename)}'),
  );
}
```

Usa el método HTTP DELETE. `Uri.encodeComponent` codifica el nombre del archivo para que sea válido en la URL.

---

## Método `getStats`

```dart
Future<DiskStats> getStats() async {
  final response = await http.get(Uri.parse(_config.statsUrl));
  return DiskStats.fromJson(jsonDecode(response.body));
}
```

---

## Método `getConfig`

```dart
Future<AppConfig> getConfig() async {
  final response = await http.get(Uri.parse(_config.configUrl));
  return AppConfig.fromJson(jsonDecode(response.body));
}
```

---

## Método `getDownloadUrl`

```dart
String getDownloadUrl(String filename) => _config.downloadUrl(filename);
```

Wrapper que delega a `ApiConfig.downloadUrl`. Permite que el `HomeScreen` obtenga la URL de descarga sin importar `ApiConfig` directamente.

---

## Método `healthCheck`

```dart
Future<bool> healthCheck() async {
  try {
    final response = await http.get(Uri.parse(_config.healthUrl))
        .timeout(const Duration(seconds: 3));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}
```

Verifica si el servidor sigue respondiendo. Retorna `false` ante cualquier error o timeout. Usado en `HomeScreen` para detectar pérdida de conexión.
