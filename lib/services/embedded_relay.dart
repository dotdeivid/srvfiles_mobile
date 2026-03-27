import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import 'mobile_server_storage_service.dart';
import 'pin_service.dart';

/// Mini servidor HTTP + WebSocket relay embebido.
///
/// Modos de operación:
/// - **Relay only** (default): solo expone GET /api/health y WebSocket /ws.
/// - **Server mode**: expone además la API REST de archivos y exige PIN en
///   todos los endpoints y conexiones WebSocket.
class EmbeddedRelay {
  HttpServer? _server;
  final Map<String, _ConnectedClient> _clients = {};
  final Map<String, _TransferSession> _transfers = {};
  String? _localIp;
  int _port = 3001;

  // ─── Server mode ───────────────────────────────────────────────────
  bool _serverModeActive = false;
  MobileServerStorageService? _storage;
  PinService? _pinService;
  String? _currentPin; // PIN en texto plano mientras el servidor está activo

  /// Tokens de sesión válidos: token → true. En memoria, se limpian al apagar.
  final Map<String, bool> _sessions = {};

  /// Rate limiting: IP → { count, blockedUntil }
  final Map<String, _RateEntry> _rateLimits = {};
  static const _maxAttempts = 5;
  static const _blockDuration = Duration(minutes: 1);

  String? _deviceName;

  bool get isRunning => _server != null;
  bool get isServerMode => _serverModeActive;
  String? get localIp => _localIp;
  int get port => _port;
  String? get currentPin => _currentPin;
  String? get url => _localIp != null ? 'http://$_localIp:$_port' : null;

  /// Actualiza el nombre del dispositivo que se devuelve en /api/health.
  void setDeviceName(String name) => _deviceName = name;

  /// Inicia el relay en el puerto dado. Intenta puertos sucesivos si está ocupado.
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

  /// Activa el modo servidor completo. Genera y retorna el PIN.
  Future<String> startServerMode() async {
    _storage = MobileServerStorageService();
    _pinService = PinService();
    _serverModeActive = true;
    _sessions.clear();
    _rateLimits.clear();
    _currentPin = await _pinService!.generatePin();
    return _currentPin!;
  }

  /// Desactiva el modo servidor, limpia sesiones y el PIN.
  Future<void> stopServerMode() async {
    _serverModeActive = false;
    _sessions.clear();
    _rateLimits.clear();
    _currentPin = null;
    await _pinService?.clearPin();
    _storage = null;
    _pinService = null;
  }

  /// Detiene el relay completo y desconecta todos los clientes.
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

  // ─── Request router ────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest req) async {
    // CORS — permitir acceso desde cualquier origen (red local)
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-SrvFiles-Token');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');

    if (req.method == 'OPTIONS') {
      req.response
        ..statusCode = HttpStatus.ok
        ..close();
      return;
    }

    // Normalizar barra final (axios envía /api/files/ con trailing slash)
    final rawPath = req.uri.path;
    final path = rawPath.length > 1 && rawPath.endsWith('/')
        ? rawPath.substring(0, rawPath.length - 1)
        : rawPath;
    final method = req.method;

    // Siempre público
    if (path == '/api/health' && method == 'GET') {
      return _handleHealth(req);
    }
    if (path == '/ws') {
      return _handleWebSocketUpgrade(req);
    }

    // Rutas del modo servidor (solo paths /api/)
    if (_serverModeActive && path.startsWith('/api/')) {
      if (path == '/api/auth' && method == 'POST') {
        return _handleAuth(req);
      }
      if (path == '/api/pin' && method == 'GET') {
        return _handlePin(req);
      }
      // Todas las demás rutas /api/ requieren token válido
      if (!_isAuthorized(req)) {
        req.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Unauthorized'}))
          ..close();
        return;
      }
      if (path == '/api/files' && method == 'GET') return _handleListFiles(req);
      if (path == '/api/files/upload' && method == 'POST') return _handleUpload(req);
      if (path.startsWith('/api/files/download/') && method == 'GET') {
        return _handleDownload(req, _decodeName(path, '/api/files/download/'));
      }
      if (path.startsWith('/api/files/') && method == 'DELETE') {
        return _handleDeleteFile(req, _decodeName(path, '/api/files/'));
      }
      if (path == '/api/files/stats' && method == 'GET') return _handleStats(req);
      if (path == '/api/config' && method == 'GET') return _handleConfig(req);
      // Ruta /api/ desconocida
      req.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Not found'}))
        ..close();
      return;
    }

    // Cualquier otra ruta → servir el frontend web desde los assets
    return _handleStaticFile(req);
  }

  // ─── Frontend estático ─────────────────────────────────────────────

  /// Sirve archivos del frontend web desde assets/www/.
  /// Redirige rutas desconocidas a index.html (SPA routing).
  Future<void> _handleStaticFile(HttpRequest req) async {
    var path = req.uri.path;
    if (path == '/' || path.isEmpty) path = '/index.html';

    final assetPath = 'assets/www$path';
    ByteData? data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (_) {
      // Archivo no encontrado → SPA fallback a index.html
      try {
        data = await rootBundle.load('assets/www/index.html');
        path = '/index.html';
      } catch (_) {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
        return;
      }
    }

    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final mimeType = _staticMimeType(path);

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, mimeType)
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..add(bytes);
    await req.response.close();
  }

  String _staticMimeType(String path) {
    if (path.endsWith('.html')) return 'text/html; charset=utf-8';
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (path.endsWith('.css')) return 'text/css; charset=utf-8';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.ico')) return 'image/x-icon';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.ttf')) return 'font/ttf';
    if (path.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  // ─── Auth ──────────────────────────────────────────────────────────

  bool _isAuthorized(HttpRequest req) {
    final token = req.headers.value('x-srvfiles-token')
        ?? req.uri.queryParameters['token']
        ?? '';
    return _sessions[token] == true;
  }

  Future<void> _handleAuth(HttpRequest req) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '';

    // Rate limiting
    final entry = _rateLimits[ip];
    if (entry != null && entry.blockedUntil.isAfter(DateTime.now())) {
      req.response
        ..statusCode = HttpStatus.tooManyRequests
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Demasiados intentos. Intentá en 60 segundos.'}))
        ..close();
      return;
    }

    Map<String, dynamic> body;
    try {
      final raw = await utf8.decodeStream(req);
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Body JSON inválido'}))
        ..close();
      return;
    }

    final pin = body['pin'] as String? ?? '';
    final valid = await _pinService!.validatePin(pin);

    if (valid) {
      _rateLimits.remove(ip);
      final token = _generateUuid();
      _sessions[token] = true;
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'token': token}))
        ..close();
    } else {
      final current = _rateLimits[ip] ?? _RateEntry(count: 0, blockedUntil: DateTime(0));
      current.count++;
      if (current.count >= _maxAttempts) {
        current.blockedUntil = DateTime.now().add(_blockDuration);
      }
      _rateLimits[ip] = current;
      req.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'PIN incorrecto'}))
        ..close();
    }
  }

  // ─── File endpoints ────────────────────────────────────────────────

  Future<void> _handleListFiles(HttpRequest req) async {
    final files = await _storage!.listFiles();
    final list = files
        .map((f) => {
              'name': f.name,
              'size': f.size,
              'createdAt': f.createdAt,
              'downloadUrl': f.downloadUrl,
            })
        .toList();
    _jsonOk(req, {'files': list, 'count': list.length});
  }

  Future<void> _handleUpload(HttpRequest req) async {
    final contentType = req.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    if (boundary == null) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing boundary')
        ..close();
      return;
    }

    final savedNames = <String>[];
    final transformer = MimeMultipartTransformer(boundary);
    final parts = await transformer.bind(req).toList();

    for (final part in parts) {
      final disposition = part.headers['content-disposition'] ?? '';
      final nameMatch = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
      if (nameMatch == null) continue;

      final fileName = nameMatch.group(1)!;
      final bytes = await part.fold<List<int>>([], (a, b) => a..addAll(b));
      final saved = await _storage!.saveFile(fileName, bytes);
      savedNames.add(saved);
    }

    _jsonOk(req, {'message': 'Archivos subidos', 'files': savedNames});
    _broadcastFilesChanged();
  }

  Future<void> _handleDownload(HttpRequest req, String fileName) async {
    final file = await _storage!.getFile(fileName);
    if (file == null) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Archivo no encontrado')
        ..close();
      return;
    }
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, mimeType)
      ..headers.set(
        'content-disposition',
        'attachment; filename="${Uri.encodeComponent(fileName)}"',
      );
    await file.openRead().pipe(req.response);
    await req.response.close();
  }

  Future<void> _handleDeleteFile(HttpRequest req, String fileName) async {
    await _storage!.deleteFile(fileName);
    _jsonOk(req, {'message': 'Eliminado'});
    _broadcastFilesChanged();
  }

  Future<void> _handleStats(HttpRequest req) async {
    final stats = await _storage!.getStats();
    _jsonOk(req, {'total': stats.total, 'used': stats.used, 'free': stats.free});
  }

  void _handleConfig(HttpRequest req) {
    _jsonOk(req, {
      'appName': 'SrvFiles Mobile',
      'lanIp': _localIp ?? '',
      'port': _port,
      'frontendPort': _port, // mismo puerto: relay sirve frontend y API juntos
      'maxFileSizeMb': 0,    // sin límite configurado
      'lanUrl': 'http://${_localIp ?? ''}:$_port',
    });
  }

  void _handlePin(HttpRequest req) {
    if (_currentPin == null) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'No server mode active'}))
        ..close();
      return;
    }
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'pin': _currentPin}))
      ..close();
  }

  void _handleHealth(HttpRequest req) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'status': 'ok',
        'app': 'srvfiles',
        'appName': _deviceName ?? 'SrvFiles',
        'relay': true,
        'serverMode': _serverModeActive,
        'clients': _clients.length,
      }))
      ..close();
  }

  // ─── WebSocket ─────────────────────────────────────────────────────

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade failed')
        ..close();
      return;
    }

    final clientId = _generateUuid();
    final rawIp = request.connectionInfo?.remoteAddress.address ?? '';
    final isLocalhost = rawIp == '127.0.0.1' || rawIp == '::1' || rawIp.isEmpty;
    final clientIp = isLocalhost
        ? (_localIp ?? rawIp)
        : rawIp.replaceAll('::ffff:', '');

    debugPrint('[Relay] nueva conexión WS: $clientId desde $clientIp serverMode=$_serverModeActive');

    _ConnectedClient? client;
    bool authenticated = !_serverModeActive; // relay-only: no auth needed

    // En relay-only mode no hay PIN: enviar auth_ok inmediatamente para que
    // los clientes web (que esperan auth_ok antes de registrarse) puedan proceder.
    if (!_serverModeActive) {
      _send(ws, {'type': 'auth_ok'});
    }

    ws.listen(
      (data) {
        // ── Binary ──
        if (data is List<int>) {
          if (!authenticated) { ws.close(4401, 'Unauthorized'); return; }
          final buf = data is Uint8List ? data : Uint8List.fromList(data);
          if (buf.length <= 36) return;
          final transferId = utf8.decode(buf.sublist(0, 36)).trim();
          final session = _transfers[transferId];
          if (session == null) return;
          final receiver = _clients[session.receiverClientId];
          if (receiver != null) {
            try { receiver.ws.add(buf); } catch (_) {}
          }
          return;
        }

        if (data is! String) return;
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        final type = msg['type'] as String?;

        // ── WS auth — primer mensaje obligatorio en server mode ──
        if (!authenticated) {
          if (type != 'auth') { ws.close(4401, 'Unauthorized'); return; }
          final token = msg['token'] as String? ?? '';
          if (_sessions[token] != true) { ws.close(4401, 'Token inválido'); return; }
          authenticated = true;
          _send(ws, {'type': 'auth_ok'});
          return;
        }

        // ── JSON signaling ──
        switch (type) {
          case 'auth':
            // En relay-only mode no hay PIN, pero los clientes web siempre
            // envían auth antes de registrarse y esperan auth_ok para continuar.
            if (!_serverModeActive) {
              _send(ws, {'type': 'auth_ok'});
            }

          case 'hello':
            client = _ConnectedClient(
              ws: ws,
              clientId: clientId,
              appName: (msg['appName'] as String?) ?? 'Unknown',
              receiving: false,
              ip: clientIp,
              deviceType: msg['deviceType'] == 'mobile' ? 'mobile' : 'desktop',
              isOwner: isLocalhost,
            );
            _clients[clientId] = client!;
            debugPrint('[Relay] hello: ${client!.appName}($clientId) registrado. Total clientes: ${_clients.length}');
            _send(ws, {'type': 'welcome', 'clientId': clientId});
            _broadcastClients();

          case 'set-receiving':
            if (client == null) return;
            client!.receiving = msg['receiving'] == true;
            _broadcastClients();

          case 'rename':
            if (client == null) return;
            final newName = ((msg['newName'] as String?) ?? '').trim();
            if (newName.isNotEmpty) {
              client!.appName = newName;
              _broadcastClients();
            }

          case 'send-request':
            if (client == null) {
              debugPrint('[Relay] send-request ignorado: client == null para $clientId');
              return;
            }
            final to = msg['to'] as String?;
            final fileName = msg['fileName'] as String?;
            final fileSize = (msg['fileSize'] as num?)?.toInt();
            final mimeType = msg['mimeType'] as String?;
            final transferId = msg['transferId'] as String?;
            debugPrint('[Relay] send-request de ${client!.appName}($clientId) → to=$to fileName=$fileName fileSize=$fileSize clients=${_clients.keys.toList()}');
            if (to == null || transferId == null) return;
            final receiver = _clients[to];
            if (receiver == null) {
              debugPrint('[Relay] send-request: receptor $to no encontrado, rechazando');
              _send(ws, {'type': 'send-reject', 'transferId': transferId, 'reason': 'offline'});
              return;
            }
            _transfers[transferId] = _TransferSession(
              transferId: transferId,
              senderClientId: clientId,
              receiverClientId: to,
              fileName: fileName ?? '',
              fileSize: fileSize ?? 0,
              mimeType: mimeType ?? 'application/octet-stream',
            );
            debugPrint('[Relay] send-request: enviando a ${receiver.appName}($to)');
            _send(receiver.ws, {
              'type': 'send-request',
              'from': clientId,
              'fromName': client!.appName,
              'fileName': fileName ?? '',
              'fileSize': fileSize ?? 0,
              'mimeType': mimeType ?? 'application/octet-stream',
              'transferId': transferId,
            });

          case 'send-accept':
            if (client == null) return;
            final transferId = msg['transferId'] as String?;
            if (transferId == null) return;
            final session = _transfers[transferId];
            if (session == null || session.receiverClientId != clientId) return;
            final sender = _clients[session.senderClientId];
            if (sender != null) {
              _send(sender.ws, {'type': 'send-accept', 'transferId': transferId});
            }

          case 'send-reject':
            if (client == null) return;
            final transferId = msg['transferId'] as String?;
            if (transferId == null) return;
            final session = _transfers[transferId];
            if (session == null || session.receiverClientId != clientId) return;
            final sender = _clients[session.senderClientId];
            if (sender != null) {
              _send(sender.ws, {'type': 'send-reject', 'transferId': transferId});
            }
            _transfers.remove(transferId);

          case 'send-cancel':
            if (client == null) return;
            final transferId = msg['transferId'] as String?;
            if (transferId == null) return;
            final session = _transfers[transferId];
            if (session == null) return;
            final otherId = session.senderClientId == clientId
                ? session.receiverClientId
                : session.senderClientId;
            final other = _clients[otherId];
            if (other != null) {
              _send(other.ws, {'type': 'send-cancel', 'transferId': transferId});
            }
            _transfers.remove(transferId);

          case 'send-complete':
            if (client == null) return;
            final transferId = msg['transferId'] as String?;
            if (transferId == null) return;
            final session = _transfers[transferId];
            if (session == null || session.senderClientId != clientId) return;
            final receiver = _clients[session.receiverClientId];
            if (receiver != null) {
              _send(receiver.ws, {'type': 'send-complete', 'transferId': transferId});
            }
            _transfers.remove(transferId);
        }
      },
      onDone: () {
        if (client != null) {
          _clients.remove(clientId);
          _broadcastClients();
        }
      },
      onError: (_) {
        if (client != null) {
          _clients.remove(clientId);
          _broadcastClients();
        }
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  void _jsonOk(HttpRequest req, Map<String, dynamic> body) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  String _decodeName(String path, String prefix) {
    return Uri.decodeComponent(path.substring(prefix.length));
  }

  void _send(WebSocket ws, Map<String, dynamic> msg) {
    try { ws.add(jsonEncode(msg)); } catch (_) {}
  }

  void _broadcastFilesChanged() {
    final data = jsonEncode({'type': 'files-changed'});
    for (final client in _clients.values) {
      try { client.ws.add(data); } catch (_) {}
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
    final data = jsonEncode({'type': 'clients', 'clients': list});
    for (final client in _clients.values) {
      try { client.ws.add(data); } catch (_) {}
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
    } catch (_) {}
    return null;
  }
}

// ─── Internal types ────────────────────────────────────────────────────

class _ConnectedClient {
  final WebSocket ws;
  final String clientId;
  String appName;
  bool receiving;
  final String ip;
  final String deviceType;
  /// true si el cliente se conectó desde localhost (dueño del relay).
  final bool isOwner;

  _ConnectedClient({
    required this.ws,
    required this.clientId,
    required this.appName,
    required this.receiving,
    required this.ip,
    required this.deviceType,
    this.isOwner = false,
  });
}

class _TransferSession {
  final String transferId;
  final String senderClientId;
  final String receiverClientId;
  final String fileName;
  final int fileSize;
  final String mimeType;

  const _TransferSession({
    required this.transferId,
    required this.senderClientId,
    required this.receiverClientId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

class _RateEntry {
  int count;
  DateTime blockedUntil;

  _RateEntry({required this.count, required this.blockedUntil});
}
