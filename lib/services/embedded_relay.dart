import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Mini servidor WebSocket relay embebido.
/// Replica exactamente la lógica de `transfer.service.ts` del backend Node.js.
/// Solo expone: GET /api/health + WebSocket /ws.
class EmbeddedRelay {
  HttpServer? _server;
  final Map<String, _ConnectedClient> _clients = {};
  final Map<String, _TransferSession> _transfers = {};
  String? _localIp;
  int _port = 3001;

  bool get isRunning => _server != null;
  String? get localIp => _localIp;
  int get port => _port;
  String? get url => _localIp != null ? 'http://$_localIp:$_port' : null;

  /// Inicia el relay en el puerto dado. Intenta puertos sucesivos si está ocupado.
  /// Puerto 0 asigna uno aleatorio (útil para tests).
  Future<void> start({int port = 3001}) async {
    _localIp = await _getLocalIp();
    _port = port;

    if (port == 0) {
      // Puerto 0: dejar que el OS asigne uno
      _server = await HttpServer.bind('0.0.0.0', 0);
      _port = _server!.port;
    } else {
      // Intentar hasta 5 puertos si está ocupado
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

  /// Detiene el relay y desconecta todos los clientes.
  Future<void> stop() async {
    // Cerrar todos los WebSockets
    for (final client in _clients.values) {
      try {
        await client.ws.close();
      } catch (_) {}
    }
    _clients.clear();
    _transfers.clear();
    await _server?.close(force: true);
    _server = null;
  }

  // ─── Request handler ──────────────────────────────────────────────

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;

    if (path == '/api/health' && request.method == 'GET') {
      _handleHealth(request);
    } else if (path == '/ws') {
      _handleWebSocketUpgrade(request);
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
    }
  }

  void _handleHealth(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'status': 'ok',
        'app': 'srvfiles',
        'relay': true,
        'clients': _clients.length,
      }))
      ..close();
  }

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
    final clientIp = (rawIp == '127.0.0.1' || rawIp == '::1' || rawIp.isEmpty)
        ? (_localIp ?? rawIp)
        : rawIp.replaceAll('::ffff:', '');

    _ConnectedClient? client;

    ws.listen(
      (data) {
        // ── Binary: relay chunk al receptor ──
        if (data is List<int>) {
          final buf = data is Uint8List ? data : Uint8List.fromList(data);
          if (buf.length <= 36) return;
          final transferId = utf8.decode(buf.sublist(0, 36)).trim();
          final session = _transfers[transferId];
          if (session == null) return;
          final receiver = _clients[session.receiverClientId];
          if (receiver != null) {
            try {
              receiver.ws.add(buf);
            } catch (_) {}
          }
          return;
        }

        // ── Text: JSON signaling ──
        if (data is! String) return;
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        final type = msg['type'] as String?;
        switch (type) {
          case 'hello':
            client = _ConnectedClient(
              ws: ws,
              clientId: clientId,
              appName: (msg['appName'] as String?) ?? 'Unknown',
              receiving: false,
              ip: clientIp,
              deviceType: msg['deviceType'] == 'mobile' ? 'mobile' : 'desktop',
            );
            _clients[clientId] = client!;
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
            if (client == null) return;
            final to = msg['to'] as String?;
            final fileName = msg['fileName'] as String?;
            final fileSize = msg['fileSize'] as int?;
            final mimeType = msg['mimeType'] as String?;
            final transferId = msg['transferId'] as String?;
            if (to == null || transferId == null) return;

            final receiver = _clients[to];
            if (receiver == null) {
              _send(ws, {
                'type': 'send-reject',
                'transferId': transferId,
                'reason': 'offline',
              });
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
            _send(receiver.ws, {
              'type': 'send-request',
              'from': clientId,
              'fromName': client!.appName,
              'fileName': fileName,
              'fileSize': fileSize,
              'mimeType': mimeType,
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

  void _send(WebSocket ws, Map<String, dynamic> msg) {
    try {
      ws.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _broadcastClients() {
    final list = _clients.values
        .map((c) => {
              'clientId': c.clientId,
              'appName': c.appName,
              'receiving': c.receiving,
              'ip': c.ip,
              'deviceType': c.deviceType,
            })
        .toList();
    final data = jsonEncode({'type': 'clients', 'clients': list});
    for (final client in _clients.values) {
      try {
        client.ws.add(data);
      } catch (_) {}
    }
  }

  String _generateUuid() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
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
      // Fallback: usar la primera dirección no-loopback
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}

// ─── Internal types ───────────────────────────────────────────────────

class _ConnectedClient {
  final WebSocket ws;
  final String clientId;
  String appName;
  bool receiving;
  final String ip;
  final String deviceType;

  _ConnectedClient({
    required this.ws,
    required this.clientId,
    required this.appName,
    required this.receiving,
    required this.ip,
    required this.deviceType,
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
