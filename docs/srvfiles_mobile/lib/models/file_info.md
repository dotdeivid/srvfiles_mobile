# models/file_info.dart

**Archivo:** `lib/models/file_info.dart`
**Rol:** Modelo que representa un archivo en el servidor o en los archivos recibidos localmente.

---

## Clase `FileInfo`

```dart
class FileInfo {
  final String name;
  final int size;           // bytes
  final String createdAt;  // ISO 8601
  final String downloadUrl; // path o URL de descarga
  // ...
}
```

---

## Constructor `fromJson`

```dart
factory FileInfo.fromJson(Map<String, dynamic> json) {
  return FileInfo(
    name: json['name'] as String,
    size: json['size'] as int,
    createdAt: json['createdAt'] as String,
    downloadUrl: json['downloadUrl'] as String,
  );
}
```

Deserializa la respuesta de `/api/files`. El servidor retorna un array de estos objetos:

```json
{
  "files": [
    {
      "name": "informe.pdf",
      "size": 204800,
      "createdAt": "2026-03-20T14:30:00.000Z",
      "downloadUrl": "/api/files/download/informe.pdf"
    }
  ]
}
```

---

## Uso dual: servidor y archivos recibidos

`FileInfo` se usa para dos propósitos diferentes:

1. **Archivos del servidor**: vienen del API, `downloadUrl` es una ruta relativa al servidor (`/api/files/download/...`).
2. **Archivos recibidos localmente**: son creados manualmente en `ReceivedFilesService`, donde `downloadUrl` es una ruta absoluta en el sistema de archivos del dispositivo (ej: `/data/user/0/.../SrvFiles/foto.jpg`).

El widget `FileListItem` usa `downloadUrl` de forma diferente según el contexto: para archivos del servidor llama `_onDownload`, para archivos recibidos llama `OpenFilex.open(file.downloadUrl)` directamente.
