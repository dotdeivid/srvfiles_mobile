# models/app_config.dart

**Archivo:** `lib/models/app_config.dart`
**Rol:** Modelo que representa la configuración del servidor backend, recibida desde el endpoint `/api/config`.

---

## Clase `AppConfig`

```dart
class AppConfig {
  final String appName;
  final String lanIp;
  final int port;
  final int maxFileSizeMb;
  // ...
}
```

Representa la respuesta JSON del servidor:

```json
{
  "appName": "SrvFiles",
  "lanIp": "192.168.1.10",
  "port": 3001,
  "maxFileSizeMb": 500
}
```

---

## Constructor `fromJson`

```dart
factory AppConfig.fromJson(Map<String, dynamic> json) {
  return AppConfig(
    appName: json['appName'] as String,
    lanIp: json['lanIp'] as String,
    port: json['port'] as int,
    maxFileSizeMb: json['maxFileSizeMb'] as int,
  );
}
```

### ¿Qué es un factory constructor?

En Dart, `factory` indica que el constructor no garantiza crear una nueva instancia (podría retornar una existente del caché, por ejemplo). Aquí se usa por convención para constructores que construyen el objeto a partir de datos externos (JSON, base de datos, etc.).

El tipo `Map<String, dynamic>` es el equivalente Dart de un objeto JSON genérico: las claves son strings y los valores pueden ser cualquier tipo (`dynamic`). La decodificación de JSON produce siempre este tipo.

### `as String`, `as int`

Los casteos explícitos convierten el tipo `dynamic` al tipo concreto. Si el JSON del servidor tuviera un campo de tipo incorrecto (ej: `"port": "3001"` en lugar de `"port": 3001`), el casteo lanzaría una excepción en runtime, lo que facilita detectar bugs de contrato de API.

---

## Uso en la app

`AppConfig` se usa en `HomeScreen` para:
- Mostrar el nombre del servidor en la AppBar (`_config?.appName`).
- Generar el QR con la URL LAN (`config.lanIp`, `config.port`).
- Validar el tamaño máximo de archivos en el `UploadSheet` (`maxFileSizeMb`).
