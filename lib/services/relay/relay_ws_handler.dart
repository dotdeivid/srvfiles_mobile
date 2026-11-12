import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../app_logger.dart';
import '../crypto_service.dart';
import '../transfer_service.dart' show chunkSize, transferIdLength;
import 'relay_types.dart';

/// Límites del relay.
const _maxClients = 50;
const _maxAppNameLength = 64;
const _maxTextMessageBytes = 64 * 1024;
// chunk + header + nonce/tag de AES-GCM, con margen.
const _maxBinaryMessageBytes = chunkSize + transferIdLength + 1024;

/// Handles WebSocket upgrade, client management, JSON signaling, key exchange,
/// and binary chunk relaying for the embedded relay.
///
/// Los mensajes de cada conexión se procesan en orden (una cola por socket), y
/// lo que se envía a cada socket también sale en orden, aunque haya que
/// cifrarlo de forma asíncrona.
class RelayWsHandler {
  final Map<String, ConnectedClient> clients;
  final Map<String, TransferSession> transfers;
  final bool Function(String token) isValidToken;
  final bool Function() isServerMode;
  final String Function() generateUuid;
  final void Function() broadcastClients;

  /// Cola de envío por socket.
  final Expando<Future<void>> _sendChains = Expando('relaySendChain');

  RelayWsHandler({
    required this.clients,
    required this.transfers,
    required this.isValidToken,
    required this.isServerMode,
    required this.generateUuid,
    required this.broadcastClients,
  });

  // ─── WebSocket upgrade ────────────────────────────────────────────

  Future<void> handleUpgrade(HttpRequest request, String? localIp) async {
    WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (e, st) {
      AppLogger.instance.error('relay_ws_handler: WebSocket upgrade fallido', error: e, stack: st);
      try {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('WebSocket upgrade failed');
        await request.response.close();
      } catch (_) {}
      return;
    }

    // Detecta clientes que perdieron la red sin cerrar el socket.
    ws.pingInterval = const Duration(seconds: 15);

    final clientId = generateUuid();
    final rawIp = request.connectionInfo?.remoteAddress.address ?? '';
    final isLocalhost = rawIp == '127.0.0.1' || rawIp == '::1' || rawIp.isEmpty;
    final clientIp = isLocalhost
        ? (localIp ?? rawIp)
        : rawIp.replaceAll('::ffff:', '');

    AppLogger.instance.debug('[Relay] nueva conexión WS: $clientId desde $clientIp serverMode=${isServerMode()}');

    final conn = _Connection(
      ws: ws,
      clientId: clientId,
      clientIp: clientIp,
      isLocalhost: isLocalhost,
      authenticated: !isServerMode(),
    );

    if (conn.authenticated) {
      conn.authOkSent = true;
      send(ws, {'type': 'auth_ok'});
    }

    Future<void> queue = Future.value();
    ws.listen(
      (data) {
        if (data is String && data.length > _maxTextMessageBytes ||
            data is List<int> && data.length > _maxBinaryMessageBytes) {
          AppLogger.instance.warn('relay_ws_handler: mensaje demasiado grande de $clientId');
          unawaited(ws.close(WebSocketStatus.messageTooBig, 'Message too big'));
          return;
        }
        queue = queue
            .then((_) => _handleMessage(conn, data))
            .catchError((Object e, StackTrace st) {
          AppLogger.instance.error('relay_ws_handler: error procesando mensaje', error: e, stack: st);
        });
      },
      onDone: () => _onClosed(conn),
      onError: (Object e) {
        AppLogger.instance.warn('relay_ws_handler: error en socket $clientId: $e');
        _onClosed(conn);
      },
      cancelOnError: true,
    );
  }

  Future<void> _handleMessage(_Connection conn, dynamic data) async {
    if (conn.closed) return;
    if (data is List<int>) {
      if (!conn.authenticated) {
        unawaited(conn.ws.close(4401, 'Unauthorized'));
        return;
      }
      final buf = data is Uint8List ? data : Uint8List.fromList(data);
      await _relayBinaryFrame(conn, buf);
      return;
    }
    if (data is String) await _processJsonMessage(conn, data);
  }

  /// Limpia el cliente y sus transferencias, y avisa a la otra parte.
  void _onClosed(_Connection conn) {
    if (conn.closed) return;
    conn.closed = true;

    final pending = transfers.values
        .where((t) =>
            t.senderClientId == conn.clientId ||
            t.receiverClientId == conn.clientId)
        .toList();
    for (final t in pending) {
      transfers.remove(t.transferId);
      final otherId = t.senderClientId == conn.clientId
          ? t.receiverClientId
          : t.senderClientId;
      final other = clients[otherId];
      if (other != null) {
        send(other.ws, {'type': 'send-cancel', 'transferId': t.transferId}, other.cipher);
      }
    }

    if (conn.client != null) {
      clients.remove(conn.clientId);
      broadcastClients();
    }
  }

  // ─── JSON message processing ─────────────────────────────────────

  Future<void> _processJsonMessage(_Connection conn, String data) async {
    final ws = conn.ws;
    Map<String, dynamic> msg;
    try {
      final raw = jsonDecode(data) as Map<String, dynamic>;
      final cipher = conn.cipher;
      if (cipher != null) {
        if (raw['type'] != 'encrypted') {
          // Con clave establecida no se aceptan mensajes en claro.
          AppLogger.instance.warn('relay_ws_handler: mensaje sin cifrar descartado (${raw['type']})');
          return;
        }
        final decrypted = await cipher.decryptJson(
          raw['iv'] as String,
          raw['data'] as String,
        );
        msg = jsonDecode(decrypted) as Map<String, dynamic>;
      } else {
        msg = raw;
      }
    } catch (e) {
      AppLogger.instance.error('relay_ws_handler: error al decodificar/descifrar mensaje', error: e);
      return;
    }

    final type = msg['type'] as String?;
    final clientId = conn.clientId;

    // WS auth — mandatory first message in server mode
    if (!conn.authenticated) {
      if (type != 'auth') { unawaited(ws.close(4401, 'Unauthorized')); return; }
      final token = msg['token'] is String ? msg['token'] as String : '';
      if (!isValidToken(token)) { unawaited(ws.close(4401, 'Token inválido')); return; }
      conn.authenticated = true;
      conn.authOkSent = true;
      send(ws, {'type': 'auth_ok'});
      return;
    }

    // JSON signaling
    switch (type) {
      case 'auth':
        // Clientes que siempre mandan auth: responder una sola vez.
        if (!conn.authOkSent) {
          conn.authOkSent = true;
          send(ws, {'type': 'auth_ok'});
        }

      case 'key-exchange':
        if (conn.cipher != null) return; // ya negociado
        final clientPubKeyB64 = msg['publicKey'] is String ? msg['publicKey'] as String : '';
        if (clientPubKeyB64.isEmpty) return;
        try {
          final result = await CryptoService.serverKeyExchange(clientPubKeyB64);
          // La respuesta va en claro: el cliente aún no tiene la clave.
          send(ws, {'type': 'key-exchange', 'publicKey': result.serverPublicKey});
          conn.cipher = result.cipher;
          conn.client?.cipher = result.cipher;
          AppLogger.instance.debug('relay_ws_handler: key exchange completo para $clientId');
        } catch (e, st) {
          AppLogger.instance.error('relay_ws_handler: key exchange fallido', error: e, stack: st);
          send(ws, {'type': 'key-exchange-error'});
        }

      case 'hello':
        if (conn.client == null && clients.length >= _maxClients) {
          unawaited(ws.close(1013, 'Demasiados clientes')); // Try Again Later
          return;
        }
        final newClient = ConnectedClient(
          ws: ws,
          clientId: clientId,
          appName: _cleanName(msg['appName']) ?? 'Unknown',
          receiving: false,
          ip: conn.clientIp,
          deviceType: msg['deviceType'] == 'mobile' ? 'mobile' : 'desktop',
          isOwner: conn.isLocalhost,
          cipher: conn.cipher,
          e2e: msg['e2e'] is num && (msg['e2e'] as num) >= 1,
        );
        conn.client = newClient;
        clients[clientId] = newClient;
        AppLogger.instance.debug('[Relay] hello: ${newClient.appName}($clientId) registrado (encrypted=${newClient.cipher != null}). Total: ${clients.length}');
        send(ws, {'type': 'welcome', 'clientId': clientId}, newClient.cipher);
        broadcastClients();

      case 'set-receiving':
        final c = conn.client;
        if (c == null) return;
        c.receiving = msg['receiving'] == true;
        broadcastClients();

      case 'rename':
        final c = conn.client;
        if (c == null) return;
        final newName = _cleanName(msg['newName']);
        if (newName != null) {
          c.appName = newName;
          broadcastClients();
        }

      case 'send-request':
        final c = conn.client;
        if (c == null) return;
        final to = msg['to'] as String?;
        final fileName = msg['fileName'] as String?;
        final fileSize = (msg['fileSize'] as num?)?.toInt();
        final mimeType = msg['mimeType'] as String?;
        final transferId = msg['transferId'] as String?;
        if (to == null || transferId == null) return;
        if (transferId.isEmpty || transferId.length > transferIdLength) return;
        // Cifrado de extremo a extremo obligatorio: sin la clave del emisor no se reenvía.
        final senderKey = _e2eField(msg, 'publicKey');
        if (!_validPublicKey(senderKey)) {
          send(ws, {'type': 'send-reject', 'transferId': transferId, 'reason': 'e2e-required'}, c.cipher);
          return;
        }
        if (transfers.containsKey(transferId)) {
          // No permitir pisar una sesión existente.
          send(ws, {'type': 'send-reject', 'transferId': transferId, 'reason': 'duplicate'}, c.cipher);
          return;
        }
        final receiver = clients[to];
        if (receiver == null || to == clientId) {
          send(ws, {'type': 'send-reject', 'transferId': transferId, 'reason': 'offline'}, c.cipher);
          return;
        }
        if (!receiver.e2e) {
          send(ws, {'type': 'send-reject', 'transferId': transferId, 'reason': 'e2e-unsupported'}, c.cipher);
          return;
        }
        transfers[transferId] = TransferSession(
          transferId: transferId,
          senderClientId: clientId,
          receiverClientId: to,
          fileName: fileName ?? '',
          fileSize: fileSize ?? 0,
          mimeType: mimeType ?? 'application/octet-stream',
        );
        send(receiver.ws, {
          'type': 'send-request',
          'from': clientId,
          'fromName': c.appName,
          'fileName': fileName ?? '',
          'fileSize': fileSize ?? 0,
          'mimeType': mimeType ?? 'application/octet-stream',
          'transferId': transferId,
          'e2e': {'publicKey': senderKey},
        }, receiver.cipher);

      case 'send-key':
        // Clave pública E2E del receptor → emisor. El relay no puede
        // descifrar el contenido: solo reenvía.
        final transferId = msg['transferId'] as String?;
        final publicKey = msg['publicKey'] as String?;
        if (transferId == null || !_validPublicKey(publicKey)) return;
        final session = transfers[transferId];
        if (session == null || session.receiverClientId != clientId || session.keySent) return;
        session.keySent = true;
        final sender = clients[session.senderClientId];
        if (sender != null) {
          send(sender.ws, {'type': 'send-key', 'transferId': transferId, 'publicKey': publicKey}, sender.cipher);
        }

      case 'send-accept':
        final transferId = msg['transferId'] as String?;
        if (transferId == null) return;
        final session = transfers[transferId];
        if (session == null || session.receiverClientId != clientId || !session.keySent) return;
        session.accepted = true;
        final sender = clients[session.senderClientId];
        if (sender != null) {
          send(sender.ws, {'type': 'send-accept', 'transferId': transferId}, sender.cipher);
        }

      case 'send-reject':
        final transferId = msg['transferId'] as String?;
        if (transferId == null) return;
        final session = transfers[transferId];
        if (session == null || session.receiverClientId != clientId) return;
        final sender = clients[session.senderClientId];
        if (sender != null) {
          send(sender.ws, {
            'type': 'send-reject',
            'transferId': transferId,
            if (msg['reason'] is String) 'reason': msg['reason'],
          }, sender.cipher);
        }
        transfers.remove(transferId);

      case 'send-cancel':
        final transferId = msg['transferId'] as String?;
        if (transferId == null) return;
        final session = transfers[transferId];
        if (session == null) return;
        if (session.senderClientId != clientId && session.receiverClientId != clientId) return;
        final otherId = session.senderClientId == clientId
            ? session.receiverClientId
            : session.senderClientId;
        final other = clients[otherId];
        if (other != null) {
          send(other.ws, {'type': 'send-cancel', 'transferId': transferId}, other.cipher);
        }
        transfers.remove(transferId);

      case 'send-complete':
        final transferId = msg['transferId'] as String?;
        if (transferId == null) return;
        final session = transfers[transferId];
        if (session == null || session.senderClientId != clientId) return;
        final receiver = clients[session.receiverClientId];
        if (receiver != null) {
          // e2e.final: marcador cifrado de extremo a extremo; se reenvía tal cual.
          send(receiver.ws, {
            'type': 'send-complete',
            'transferId': transferId,
            'e2e': {'final': _e2eField(msg, 'final')},
          }, receiver.cipher);
        }
        transfers.remove(transferId);
    }
  }

  // ─── Binary relay ────────────────────────────────────────────────

  Future<void> _relayBinaryFrame(_Connection conn, Uint8List buf) async {
    Uint8List payload;
    final senderCipher = conn.cipher;
    if (senderCipher != null) {
      try {
        payload = await senderCipher.decryptBinary(buf);
      } catch (e) {
        AppLogger.instance.error('relay_ws_handler: fallo al descifrar chunk binario', error: e);
        return;
      }
    } else {
      payload = buf;
    }

    if (payload.length <= transferIdLength) return;
    final transferId = utf8.decode(payload.sublist(0, transferIdLength), allowMalformed: true).trim();
    final session = transfers[transferId];
    // Solo el emisor de la sesión puede mandar chunks, y solo tras aceptar.
    if (session == null || session.senderClientId != conn.clientId || !session.accepted) {
      return;
    }
    final receiver = clients[session.receiverClientId];
    if (receiver == null) return;

    _enqueueSend(receiver.ws, () async {
      final cipher = receiver.cipher;
      return cipher != null ? await cipher.encryptBinary(payload) : payload;
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  /// Envía [msg] a [ws], cifrado con [cipher] si se indica. Respeta el orden
  /// de los envíos anteriores al mismo socket.
  void send(WebSocket ws, Map<String, dynamic> msg, [SessionCipher? cipher]) {
    final text = jsonEncode(msg);
    _enqueueSend(ws, () async {
      if (cipher == null) return text;
      final encrypted = await cipher.encryptJson(text);
      return jsonEncode({'type': 'encrypted', ...encrypted});
    });
  }

  void _enqueueSend(WebSocket ws, Future<Object> Function() build) {
    final previous = _sendChains[ws] ?? Future<void>.value();
    _sendChains[ws] = previous.then((_) async {
      try {
        final data = await build();
        if (ws.readyState == WebSocket.open) ws.add(data);
      } catch (e) {
        AppLogger.instance.warn('relay_ws_handler: envío fallido: $e');
      }
    });
  }

  static String? _e2eField(Map<String, dynamic> msg, String key) {
    final obj = msg['e2e'];
    if (obj is! Map) return null;
    final value = obj[key];
    return value is String ? value : null;
  }

  /// base64 de una clave P-256 sin comprimir (65 bytes).
  static bool _validPublicKey(String? b64) {
    if (b64 == null) return false;
    try {
      final raw = base64.decode(b64);
      return raw.length == 65 && raw[0] == 0x04;
    } catch (_) {
      return false;
    }
  }

  static String? _cleanName(Object? value) {
    if (value is! String) return null;
    var name = value.replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
    if (name.isEmpty) return null;
    if (name.length > _maxAppNameLength) name = name.substring(0, _maxAppNameLength);
    return name;
  }
}

/// Estado de una conexión WebSocket mientras está abierta.
class _Connection {
  final WebSocket ws;
  final String clientId;
  final String clientIp;
  final bool isLocalhost;
  bool authenticated;
  bool authOkSent = false;
  bool closed = false;
  SessionCipher? cipher;
  ConnectedClient? client;

  _Connection({
    required this.ws,
    required this.clientId,
    required this.clientIp,
    required this.isLocalhost,
    required this.authenticated,
  });
}
