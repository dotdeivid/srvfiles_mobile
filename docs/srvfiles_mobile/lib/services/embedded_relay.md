# services/embedded_relay.dart

**Archivo:** `lib/services/embedded_relay.dart`
**Rol:** Servidor relay WebSocket completo corriendo dentro de la app móvil. Permite que otros dispositivos en la red se conecten al celular como si fuera un servidor SrvFiles.

---

## Concepto: ¿Relay embebido en el móvil?

La app de escritorio (Tauri) incluye un backend Node.js. Pero el móvil no puede incluir un proceso Node.js. En cambio, esta clase implementa el mismo relay WebSocket directamente en Dart usando `dart:io`.

Cuando el relay está activo, el celular actúa como hub: otros dispositivos pueden conectarse a él, verse entre sí, y transferirse archivos P2P sin necesidad de ningún servidor externo.

---

## Clase `EmbeddedRelay`

```dart
class EmbeddedRelay {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int? port;
  String? localIp;
}
```

`isRunning`, `port`, y `localIp` son leídos por `HomeScreen` para mostrar la dirección del relay en la AppBar.

---

## Método `start`

```dart
Future<void> start() async {
  // Intentar puertos 3001, 3002, 3003...
  for (int tryPort = 3001; tryPort <= 3010; tryPort++) {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, tryPort);
      port = tryPort;
      localIp = await _getLocalIp();
      _server!.listen(_handleRequest);
      return;
    } catch (_) {
      // Puerto ocupado, probar el siguiente
    }
  }
}
```

Intenta vincularse a los puertos 3001-3010. Si el 3001 está ocupado (por ejemplo, hay un servidor de escritorio en la misma máquina), prueba el 3002, etc. `InternetAddress.anyIPv4` (`0.0.0.0`) acepta conexiones de cualquier interfaz de red.

---

## Método `stop`

```dart
Future<void> stop() async {
  await _server?.close(force: true);
  _server = null;
  port = null;
}
```

---

## Método `_handleRequest`

```dart
void _handleRequest(HttpRequest request) {
  final path = request.uri.path;
  if (path == '/api/health') {
    _handleHealth(request);
  } else if (WebSocketTransformer.isUpgradeRequest(request)) {
    _handleWebSocketUpgrade(request);
  } else {
    request.response
      ..statusCode = HttpStatus.notFound
      ..close();
  }
}
```

El servidor HTTP nativo de Dart recibe todas las peticiones aquí. Se distinguen dos casos:
- Petición GET a `/api/health`: responde con el JSON de estado para el descubrimiento.
- Petición de upgrade a WebSocket: la maneja el relay.

### `WebSocketTransformer.isUpgradeRequest`

Una conexión WebSocket empieza como una petición HTTP normal con un header especial `Upgrade: websocket`. `WebSocketTransformer.isUpgradeRequest` detecta ese header.

---

## Método `_handleHealth`

```dart
void _handleHealth(HttpRequest request) async {
  final deviceName = await DeviceNameService().getName();
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.set('Content-Type', 'application/json')
    ..headers.set('Access-Control-Allow-Origin', '*')
    ..write(jsonEncode({
      'status': 'ok',
      'app': 'SrvFiles',
      'appName': deviceName,
    }))
    ..close();
}
```

Responde con el mismo formato que el backend Node.js. `'app': 'SrvFiles'` es lo que verifica `DiscoveryService.probe()` para reconocer el servidor.

---

## Método `_handleWebSocketUpgrade`

```dart
void _handleWebSocketUpgrade(HttpRequest request) async {
  final ws = await WebSocketTransformer.upgrade(request);
  final clientId = _generateUuid();
  final rawIp = request.connectionInfo?.remoteAddress.address ?? '';
  // ...registro del cliente y listeners...
}
```

Hace el handshake del upgrade y crea la conexión WebSocket. A partir de aquí, la lógica es idéntica a `handleConnection` en `transfer.service.ts` del backend:

- Mensaje `hello` → registra cliente, envía `welcome`, hace broadcast.
- Mensaje `send-request` → verifica receptor, crea sesión, reenvía.
- Mensaje `send-accept` / `send-reject` / `send-cancel` / `send-complete` → notifica a la otra parte.
- Mensaje binario → extrae `transferId` de los primeros 36 bytes, reenvía al receptor.
- Cierre → elimina cliente, hace broadcast.

---

## Clases internas `_ConnectedClient` y `_TransferSession`

```dart
class _ConnectedClient {
  final WebSocket ws;
  final String clientId;
  String appName;
  bool receiving;
  final String ip;
  final String deviceType;
  final bool isServer;
}

class _TransferSession {
  final String transferId;
  final String senderClientId;
  final String receiverClientId;
  final String fileName;
  final int fileSize;
  final String mimeType;
}
```

Equivalentes exactas a `ConnectedClient` y `TransferSession` del backend Node.js. El estado se guarda en Maps locales al relay:

```dart
final _clients = <String, _ConnectedClient>{};
final _transfers = <String, _TransferSession>{};
```

---

## Función `_generateUuid`

```dart
String _generateUuid() {
  final rand = Random.secure();
  final bytes = List.generate(16, (_) => rand.nextInt(256));
  // Formato UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  // ...formatear como hex con guiones...
}
```

Genera un UUID v4 usando `Random.secure()` (generador criptográficamente seguro). Los bits 6 y 8 son modificados con operaciones de bitmask para cumplir con el estándar UUID v4.
