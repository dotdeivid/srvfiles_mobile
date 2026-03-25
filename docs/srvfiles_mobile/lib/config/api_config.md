# config/api_config.dart

**Archivo:** `lib/config/api_config.dart`
**Rol:** Centraliza la construcción de URLs para todas las llamadas HTTP y WebSocket al backend. Todos los servicios obtienen sus endpoints de aquí.

---

## Clase `ApiConfig`

```dart
class ApiConfig {
  const ApiConfig(this.baseUrl);
  final String baseUrl;
  // ...
}
```

Encapsula la URL base del servidor (ej: `http://192.168.1.10:3001`) y expone getters para cada endpoint. Al centralizar las URLs, cambiar el puerto o la ruta del API solo requiere modificar un lugar.

---

## Getter `wsUrl`

```dart
String get wsUrl =>
    baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
```

Convierte la URL HTTP en WebSocket reemplazando el esquema:
- `http://192.168.1.10:3001` → `ws://192.168.1.10:3001`
- `https://...` → `wss://...`

El regex `^http` solo reemplaza al inicio del string (por el `^`), así que una URL que contenga "http" en el path no se altera.

---

## Getter `healthUrl`

```dart
String get healthUrl => '$baseUrl/api/health';
```

Para descubrimiento y verificación de conectividad. El `discovery_service.dart` llama este endpoint para confirmar que un servidor es SrvFiles.

---

## Getter `filesUrl`

```dart
String get filesUrl => '$baseUrl/api/files';
```

Raíz del API de archivos. `files_service.dart` agrega subrutas como `/upload`, `/download/:name`, etc.

---

## Getter `statsUrl`

```dart
String get statsUrl => '$baseUrl/api/files/stats';
```

Endpoint de estadísticas de disco. Retorna `{ total, free, used }` en bytes.

---

## Getter `configUrl`

```dart
String get configUrl => '$baseUrl/api/config';
```

Endpoint que devuelve la configuración del servidor: nombre de la app, IP LAN, puerto, límite de tamaño de archivo.

---

## Método `downloadUrl`

```dart
String downloadUrl(String filename) =>
    '$baseUrl/api/files/download/${Uri.encodeComponent(filename)}';
```

Genera la URL de descarga para un archivo específico. `Uri.encodeComponent` es el equivalente Dart de `encodeURIComponent` en JavaScript: codifica caracteres especiales como espacios (`%20`), ampersands, etc., para que el nombre del archivo sea válido en una URL.

Ejemplo: `foto de vacaciones.jpg` → `foto%20de%20vacaciones.jpg`.
