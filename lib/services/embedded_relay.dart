import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
class EmbeddedRelay {
  HttpServer? _server;
  final Map<String, ConnectedClient> _clients = {};
  final Map<String, TransferSession> _transfers = {};
  String? _localIp;
  int _port = 3001;

  // Server mode
  bool _serverModeActive = false;
  MobileServerStorageService? _storage;
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
      sessions: _auth.sessions,
      isServerMode: () => _serverModeActive,
      generateUuid: _generateUuid,
      broadcastClients: _broadcastClients,
      broadcastFilesChanged: _broadcastFilesChanged,
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

  /// Sets the device name returned in /api/health.
  void setDeviceName(String name) => _deviceName = name;

  // ─── Lifecycle ────────────────────────────────────────────────────

  /// Starts the relay on the given port. Tries successive ports if busy.
  Future<void> start({int port = 3001}) async {
    _localIp = await _getLocalIp();
    _port = port;

    if (port == 0) {
      _server = await HttpServer.bind('0.0.0.0', 0);
      _port = _server!.port;
    } else {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          _server = await HttpServer.bind('0.0.0.0', _port);
          break;
        } on SocketException {
          _port++;
        }
      }
      if (_server == null) {
        throw Exception('No se pudo iniciar el relay en ningún puerto');
      }
    }

    _server!.listen(_handleRequest);
  }

  /// Activates full server mode. Returns the generated PIN.
  Future<String> startServerMode() async {
    _storage = MobileServerStorageService();
    _pinService = PinService();
    _serverModeActive = true;
    _auth.clear();
    _auth.pinService = _pinService;
    _httpHandler.storage = _storage;
    final pin = await _pinService!.generatePin();
    _auth.currentPin = pin;
    return pin;
  }

  /// Deactivates server mode, clears sessions and PIN.
  Future<void> stopServerMode() async {
    _serverModeActive = false;
    _auth.clear();
    await _pinService?.clearPin();
    _storage = null;
    _pinService = null;
    _httpHandler.storage = null;
  }

  /// Stops the relay and disconnects all clients.
  Future<void> stop() async {
    await stopServerMode();
    for (final client in _clients.values) {
      try { await client.ws.close(); } catch (_) {}
    }
    _clients.clear();
    _transfers.clear();
    await _server?.close(force: true);
    _server = null;
  }

  // ─── Request router ───────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest req) async {
    // CORS
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-SrvFiles-Token');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');

    if (req.method == 'OPTIONS') {
      req.response
        ..statusCode = HttpStatus.ok
        ..close();
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
      if (path == '/api/pin' && method == 'GET') {
        return _auth.handlePin(req);
      }
      // All other /api/ routes require valid token
      if (!_auth.isAuthorized(req)) {
        req.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Unauthorized'}))
          ..close();
        return;
      }
      if (path == '/api/files' && method == 'GET') return _httpHandler.handleListFiles(req);
      if (path == '/api/files/upload' && method == 'POST') return _httpHandler.handleUpload(req);
      if (path.startsWith('/api/files/download/') && method == 'GET') {
        return _httpHandler.handleDownload(req, _decodeName(path, '/api/files/download/'));
      }
      if (path.startsWith('/api/files/') && method == 'DELETE') {
        return _httpHandler.handleDeleteFile(req, _decodeName(path, '/api/files/'));
      }
      if (path == '/api/files/stats' && method == 'GET') return _httpHandler.handleStats(req);
      if (path == '/api/config' && method == 'GET') {
        return _httpHandler.handleConfig(req, localIp: _localIp, port: _port);
      }
      // Unknown /api/ route
      req.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Not found'}))
        ..close();
      return;
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
            })
        .toList();
    final msg = {'type': 'clients', 'clients': list};
    for (final client in _clients.values) {
      _wsHandler.send(client.ws, msg, client.cipher);
    }
  }

  // ─── Utilities ────────────────────────────────────────────────────

  String _decodeName(String path, String prefix) {
    return Uri.decodeComponent(path.substring(prefix.length));
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

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      AppLogger.instance.error('embedded_relay: error al obtener IP local', error: e);
    }
    return null;
  }
}
