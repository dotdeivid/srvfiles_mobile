import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../config/api_config.dart';
import '../utils/local_network.dart';
import 'mobile_server_storage_service.dart';
import 'pin_service.dart';
import 'app_logger.dart';
import 'relay/relay_types.dart';
import 'relay/relay_auth.dart';
import 'relay/relay_http_handler.dart';
import 'relay/relay_ws_handler.dart';

/// Mini HTTP + WebSocket relay server embedded in the mobile app.
///
/// Modes:
/// - **Relay only** (default): GET /api/health + WebSocket /ws only.
/// - **Server mode**: full REST API for files + PIN auth.
///
/// Delegates handling to:
/// - [RelayAuth] — auth endpoints, rate limiting, session tokens
/// - [RelayHttpHandler] — REST file endpoints, static file serving
/// - [RelayWsHandler] — WebSocket upgrade, signaling, binary relay
///
/// La app usa una única instancia ([shared]) que vive mientras la app está
/// abierta, para que cambiar de pantalla no reinicie el relay ni lo mueva de
/// puerto.
class EmbeddedRelay {
  /// Instancia compartida por toda la app.
  static final EmbeddedRelay shared = EmbeddedRelay();

  HttpServer? _server;
  Future<void>? _starting;
  Future<void>? _stopping;
  final Map<String, ConnectedClient> _clients = {};
  final Map<String, TransferSession> _transfers = {};
  String? _localIp;
  int _port = defaultServerPort;

  // Server mode
  bool _serverModeActive = false;
  PinService? _pinService;

  String? _deviceName;

  // Sub-handlers
  final RelayAuth _auth = RelayAuth();
  final RelayHttpHandler _httpHandler = RelayHttpHandler();
  late final RelayWsHandler _wsHandler;

  EmbeddedRelay() {
    _wsHandler = RelayWsHandler(
      clients: _clients,
      transfers: _transfers,
      isValidToken: _auth.isValidToken,
      isServerMode: () => _serverModeActive,
      generateUuid: _generateUuid,
      broadcastClients: _broadcastClients,
    );
    _httpHandler.onFilesChanged = _broadcastFilesChanged;
  }

  // ─── Public getters ───────────────────────────────────────────────

  bool get isRunning => _server != null;
  bool get isServerMode => _serverModeActive;
  String? get localIp => _localIp;
  int get port => _port;
  String? get currentPin => _auth.currentPin;
  String? get url => _localIp != null ? 'http://$_localIp:$_port' : null;

  /// URL de loopback para que la propia app hable con el relay.
  String get loopbackUrl => 'http://127.0.0.1:$_port';

  /// Sets the device name returned in /api/health.
  void setDeviceName(String name) => _deviceName = name;

  // ─── Lifecycle ────────────────────────────────────────────────────

  /// Starts the relay on the given port. Tries successive ports if busy.
  /// Si ya está corriendo no hace nada (solo refresca la IP local).
  Future<void> start({int port = defaultServerPort}) async {
    // Esperar un stop en curso: si no, el puerto sigue ocupado y el relay
    // terminaría en 3002+, donde el descubrimiento no lo encuentra.
    if (_stopping != null) await _stopping;
    if (_server != null) {
      _localIp = await getLocalIpv4() ?? _localIp;
      return;
    }
    if (_starting != null) return _starting;
    final future = _doStart(port);
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _doStart(int port) async {
    _localIp = await getLocalIpv4();
    _port = port;

    if (port == 0) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
    } else {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
          break;
        } on SocketException {
          _port++;
        }
      }
      if (_server == null) {
        throw Exception('No se pudo iniciar el relay en ningún puerto');
      }
    }
    if (_port != port && port != 0) {
      AppLogger.instance.warn('embedded_relay: puerto $port ocupado, usando $_port');
    }

    _server!.listen((req) => unawaited(_handleRequest(req)));
  }

  /// Activates full server mode. Returns the generated PIN.
  Future<String> startServerMode({MobileServerStorageService? storage}) async {
    _httpHandler.storage = storage ?? MobileServerStorageService();
    _pinService = PinService();
    _auth.clear();
    _auth.pinService = _pinService;
    final pin = _pinService!.generatePin();
    _serverModeActive = true;
    return pin;
  }

  /// Deactivates server mode, clears sessions and PIN.
  ///
  /// Cierra también los sockets abiertos, para que nadie siga autenticado
  /// con un token del modo servidor anterior.
  Future<void> stopServerMode() async {
    final wasActive = _serverModeActive;
    _serverModeActive = false;
    _auth.clear();
    _pinService?.clearPin();
    _pinService = null;
    _auth.pinService = null;
    _httpHandler.storage = null;
    if (wasActive) await _disconnectAll();
  }

  /// Stops the relay and disconnects all clients.
  Future<void> stop() {
    return _stopping ??= _doStop().whenComplete(() => _stopping = null);
  }

  Future<void> _doStop() async {
    if (_starting != null) await _starting;
    await stopServerMode();
    await _disconnectAll();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// Crea una sesión para la propia app (dueña del relay) sin pasar por HTTP.
  String issueLocalToken() => _auth.createSession(_generateUuid());

  Future<void> _disconnectAll() async {
    final sockets = _clients.values.map((c) => c.ws).toList();
    _clients.clear();
    _transfers.clear();
    for (final ws in sockets) {
      try { await ws.close(); } catch (_) {}
    }
  }

  // ─── Request router ───────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      await _route(req);
    } catch (e, st) {
      AppLogger.instance.error('embedded_relay: error atendiendo ${req.method} ${req.uri.path}', error: e, stack: st);
      try {
        req.response
          ..statusCode = HttpStatus.internalServerError
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Error interno'}));
        await req.response.close();
      } catch (_) {
        // La respuesta ya se había empezado a enviar.
      }
    }
  }

  Future<void> _route(HttpRequest req) async {
    // CORS: necesario para clientes de otro origen (app de escritorio Tauri).
    // La autenticación va por cabecera, no por cookies.
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-SrvFiles-Token, Range');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.ok;
      await req.response.close();
      return;
    }

    final rawPath = req.uri.path;
    final path = rawPath.length > 1 && rawPath.endsWith('/')
        ? rawPath.substring(0, rawPath.length - 1)
        : rawPath;
    final method = req.method;

    // Always public
    if (path == '/api/health' && method == 'GET') {
      return _httpHandler.handleHealth(req,
        deviceName: _deviceName,
        serverModeActive: _serverModeActive,
        clientCount: _clients.length,
        port: _port,
      );
    }
    if (path == '/ws') {
      return _wsHandler.handleUpgrade(req, _localIp);
    }

    // Server mode routes
    if (_serverModeActive && path.startsWith('/api/')) {
      if (path == '/api/auth' && method == 'POST') {
        return _auth.handleAuth(req, _generateUuid);
      }
      // Descargas y vistas previas: cabecera o token de enlace (?dl=) emitido
      // para ese archivo (el navegador no manda cabeceras en <a>/<img>/<video>).
      for (final (prefix, inline) in [('/api/files/download/', false), ('/api/files/preview/', true)]) {
        if (path.startsWith(prefix) && method == 'GET') {
          final name = _decodeName(path, prefix);
          if (name == null) return _json(req, HttpStatus.badRequest, {'error': 'Nombre inválido'});
          final link = req.uri.queryParameters['dl'] ?? '';
          if (!_auth.isAuthorized(req) && !_auth.isValidLinkToken(link, name)) {
            return _json(req, HttpStatus.unauthorized, {'error': 'Unauthorized'});
          }
          return _httpHandler.handleDownload(req, name, inline: inline);
        }
      }
      if (!_auth.isAuthorized(req)) {
        return _json(req, HttpStatus.unauthorized, {'error': 'Unauthorized'});
      }
      if (path == '/api/files' && method == 'GET') return _httpHandler.handleListFiles(req);
      if (path == '/api/files/upload' && method == 'POST') return _httpHandler.handleUpload(req);
      if (path == '/api/files/stats' && method == 'GET') return _httpHandler.handleStats(req);
      if (path == '/api/files/link' && method == 'POST') {
        return _httpHandler.handleLink(req, (name) => _auth.createLinkToken(name, _generateUuid()));
      }
      if (path.startsWith('/api/files/') && method == 'DELETE') {
        final name = _decodeName(path, '/api/files/');
        if (name == null) return _json(req, HttpStatus.badRequest, {'error': 'Nombre inválido'});
        return _httpHandler.handleDeleteFile(req, name);
      }
      if (path == '/api/config' && method == 'GET') {
        return _httpHandler.handleConfig(req, localIp: _localIp, port: _port);
      }
      // Unknown /api/ route
      return _json(req, HttpStatus.notFound, {'error': 'Not found'});
    }

    // Fallback: serve frontend static files
    return _httpHandler.handleStaticFile(req);
  }

  // ─── Broadcast helpers ────────────────────────────────────────────

  void _broadcastFilesChanged() {
    final msg = {'type': 'files-changed'};
    for (final client in _clients.values) {
      _wsHandler.send(client.ws, msg, client.cipher);
    }
  }

  void _broadcastClients() {
    final list = _clients.values
        .map((c) => {
              'clientId': c.clientId,
              'appName': c.appName,
              'receiving': c.receiving,
              'ip': c.ip,
              'deviceType': c.deviceType,
              'isOwner': c.isOwner,
              'e2e': c.e2e,
            })
        .toList();
    final msg = {'type': 'clients', 'clients': list};
    for (final client in _clients.values) {
      _wsHandler.send(client.ws, msg, client.cipher);
    }
  }

  // ─── Utilities ────────────────────────────────────────────────────

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  /// Decodifica el nombre de archivo de la ruta. Null si la codificación es
  /// inválida. La validación de rutas (`/`, `..`) la hace el almacenamiento.
  String? _decodeName(String path, String prefix) {
    try {
      final name = Uri.decodeComponent(path.substring(prefix.length));
      return name.isEmpty ? null : name;
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  String _generateUuid() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
