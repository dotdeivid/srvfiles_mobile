# services/embedded_relay.dart

**Archivo:** `lib/services/embedded_relay.dart`
**Rol:** Servidor HTTP + WebSocket completo corriendo dentro de la app móvil. Opera en dos modos: **relay puro** (solo WebSocket P2P) y **server mode** (REST API completa + frontend web embebido + WebSocket P2P).

---

## Concepto: ¿Servidor embebido en el móvil?

La app de escritorio (Tauri) incluye un backend Node.js. El móvil no puede incluir un proceso Node.js, pero implementa el mismo servidor directamente en Dart usando `dart:io`. Cuando el server mode está activo, cualquier navegador de la red puede abrir la IP del celular y ver la UI web completa de SrvFiles.

---

## Clase `EmbeddedRelay`

```dart
class EmbeddedRelay {
  HttpServer? _server;
  bool get isRunning => _server != null;
  bool get isServerMode => _serverModeActive;
  int get port => _port;
  String? get localIp => _localIp;
  String? get currentPin => _currentPin;  // PIN en texto plano mientras el servidor está activo
  String? get url => isRunning ? 'http://$_localIp:$_port' : null;
}
```

---

## Método `start`

```dart
Future<void> start() async {
  for (int tryPort = 3001; tryPort <= 3010; tryPort++) {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, tryPort);
      _port = tryPort;
      _localIp = await _getLocalIp();
      _server!.listen(_handleRequest);
      return;
    } catch (_) { /* Puerto ocupado, probar el siguiente */ }
  }
}
```

Intenta vincularse a los puertos 3001-3010. `InternetAddress.anyIPv4` (`0.0.0.0`) acepta conexiones de cualquier interfaz de red.

---

## Método `startServerMode`

```dart
Future<String> startServerMode() async {
  _serverModeActive = true;
  final pin = _generatePin();
  final hash = _hashPin(pin);
  _pinHash = hash;
  _currentPin = pin;    // Guardado en texto plano para mostrarlo en la UI
  _validTokens.clear();
  return pin;
}

void stopServerMode() {
  _serverModeActive = false;
  _pinHash = null;
  _currentPin = null;
  _validTokens.clear();
}
```

Activa el modo servidor: genera un PIN de 6 dígitos, lo hashea (SHA-256) para validación, y lo guarda en texto plano para mostrarlo en el ConnectSheet.

---

## Método `_handleRequest` — router principal

```dart
void _handleRequest(HttpRequest request) {
  // Normalizar trailing slash
  final path = request.uri.path.endsWith('/') && request.uri.path.length > 1
      ? request.uri.path.substring(0, request.uri.path.length - 1)
      : request.uri.path;

  // Auth solo para rutas /api/ (los archivos estáticos son públicos)
  if (_serverModeActive && path.startsWith('/api/')) {
    if (!_checkAuth(request)) {
      _sendJson(request, {'error': 'Unauthorized'}, status: 401);
      return;
    }
  }

  if (path == '/api/health')       { _handleHealth(request); }
  else if (path == '/api/auth')    { _handleAuth(request); }
  else if (path == '/api/pin')     { _handlePin(request); }
  else if (path == '/api/config')  { _handleConfig(request); }
  else if (path == '/api/files')   { _handleFiles(request); }
  else if (path.startsWith('/api/files/')) { _handleFilesOp(request, path); }
  else if (WebSocketTransformer.isUpgradeRequest(request)) { _handleWebSocketUpgrade(request); }
  else { _serveStaticFile(request, path); }  // Frontend web embebido
}
```

**Puntos clave:**
- El trailing slash se normaliza para que `/api/files/` y `/api/files` funcionen igual.
- La autenticación solo aplica a rutas `/api/` — los archivos estáticos son siempre públicos (necesario para que el browser cargue la app antes de autenticar).
- Las rutas `/api/` desconocidas devuelven 404 JSON (no caen al handler de archivos estáticos).

---

## Endpoint `POST /api/auth`

```dart
void _handleAuth(HttpRequest request) async {
  final body = jsonDecode(await utf8.decodeStream(request));
  final pin = body['pin'] as String?;
  if (_verifyPin(pin)) {
    final token = _generateUuid();
    _validTokens.add(token);
    _sendJson(request, {'token': token});
  } else {
    _sendJson(request, {'error': 'PIN incorrecto'}, status: 401);
  }
}
```

---

## Endpoint `GET /api/pin`

```dart
void _handlePin(HttpRequest request) {
  final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
  final isLoopback = remoteIp == '127.0.0.1' || remoteIp == '::1';
  if (!isLoopback) {
    _sendJson(request, {'error': 'Forbidden'}, status: 403);
    return;
  }
  _sendJson(request, {'pin': _currentPin ?? ''});
}
```

Solo accesible desde loopback — el frontend web (servido por el propio relay) lo llama para auto-autenticarse sin que el usuario tenga que ingresar el PIN manualmente.

---

## Endpoint `GET /api/config`

Devuelve todos los campos que el frontend espera:

```dart
_sendJson(request, {
  'appName': deviceName,
  'lanIp': _localIp,
  'port': _port,
  'frontendPort': _port,   // En mobile, frontend y backend usan el mismo puerto
  'maxFileSizeMb': 0,
  'lanUrl': 'http://$_localIp:$_port',
});
```

---

## Método `_handleWebSocketUpgrade`

```dart
void _handleWebSocketUpgrade(HttpRequest request) async {
  final ws = await WebSocketTransformer.upgrade(request);
  final clientId = _generateUuid();

  if (_serverModeActive) {
    // Enviar auth_ok inmediatamente — el cliente enviará auth con token
    ws.add(jsonEncode({'type': 'auth_ok'}));
  } else {
    // Relay puro: sin PIN, enviar auth_ok directamente
    ws.add(jsonEncode({'type': 'auth_ok'}));
  }
  // ... registro del cliente y handlers de mensajes ...
}
```

El handshake WebSocket sigue el protocolo estándar: `auth` → `auth_ok` → `hello` → `welcome`.

---

## Archivos estáticos (`_serveStaticFile`)

```dart
void _serveStaticFile(HttpRequest request, String path) async {
  final assetPath = path == '/' ? 'assets/www/index.html' : 'assets/www$path';
  final data = await rootBundle.load(assetPath);
  // ... detectar MIME type y enviar ...
}
```

Sirve el frontend web compilado desde los assets de Flutter (`assets/www/`). Permite que cualquier navegador de la red abra `http://IP:puerto` y vea la UI.

---

## Clases internas

### `_ConnectedClient`
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
```

### `_TransferSession`
```dart
class _TransferSession {
  final String transferId;
  final String senderClientId;
  final String receiverClientId;
  final String fileName;
  final int fileSize;
  final String mimeType;
}
```

Equivalentes exactas a las del backend Node.js. El estado se guarda en Maps locales:

```dart
final _clients   = <String, _ConnectedClient>{};
final _transfers = <String, _TransferSession>{};
final _validTokens = <String>{};
```
