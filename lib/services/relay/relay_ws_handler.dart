import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../app_logger.dart';
import '../crypto_service.dart';
import 'relay_types.dart';

/// Handles WebSocket upgrade, client management, JSON signaling, key exchange,
/// and binary chunk relaying for the embedded relay.
class RelayWsHandler {
  final Map<String, ConnectedClient> clients;
  final Map<String, TransferSession> transfers;
  final Map<String, bool> sessions;
  final bool Function() isServerMode;
  final String Function() generateUuid;
  final void Function() broadcastClients;
  final void Function() broadcastFilesChanged;

  RelayWsHandler({
    required this.clients,
    required this.transfers,
    required this.sessions,
    required this.isServerMode,
    required this.generateUuid,
    required this.broadcastClients,
    required this.broadcastFilesChanged,
  });

  // ─── WebSocket upgrade ────────────────────────────────────────────

  Future<void> handleUpgrade(HttpRequest request, String? localIp) async {
    WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (e, st) {
      AppLogger.instance.error('relay_ws_handler: WebSocket upgrade fallido', error: e, stack: st);
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade failed')
        ..close();
      return;
    }

    final clientId = generateUuid();
    final rawIp = request.connectionInfo?.remoteAddress.address ?? '';
    final isLocalhost = rawIp == '127.0.0.1' || rawIp == '::1' || rawIp.isEmpty;
    final clientIp = isLocalhost
        ? (localIp ?? rawIp)
        : rawIp.replaceAll('::ffff:', '');

    debugPrint('[Relay] nueva conexión WS: $clientId desde $clientIp serverMode=${isServerMode()}');

    ConnectedClient? client;
    bool authenticated = !isServerMode();
    SessionCipher? pendingCipher;

    if (!isServerMode()) {
      send(ws, {'type': 'auth_ok'});
    }

    ws.listen(
      (data) {
        if (data is List<int>) {
          if (!authenticated) { ws.close(4401, 'Unauthorized'); return; }
          final buf = data is Uint8List ? data : Uint8List.fromList(data);
          unawaited(_relayBinaryFrame(buf, client?.cipher ?? pendingCipher));
          return;
        }

        if (data is! String) return;

        unawaited(_processJsonMessage(
          ws: ws,
          data: data,
          clientId: clientId,
          clientIp: clientIp,
          isLocalhost: isLocalhost,
          localIp: localIp,
          authenticated: () => authenticated,
          setAuthenticated: (v) => authenticated = v,
          getClient: () => client,
          setClient: (c) => client = c,
          getPendingCipher: () => pendingCipher,
          setPendingCipher: (c) => pendingCipher = c,
        ));
      },
      onDone: () {
        if (client != null) {
          clients.remove(clientId);
          broadcastClients();
        }
      },
      onError: (_) {
        if (client != null) {
          clients.remove(clientId);
          broadcastClients();
        }
      },
    );
  }

  // ─── JSON message processing ─────────────────────────────────────

  Future<void> _processJsonMessage({
    required WebSocket ws,
    required String data,
    required String clientId,
    required String clientIp,
    required bool isLocalhost,
    required String? localIp,
    required bool Function() authenticated,
    required void Function(bool) setAuthenticated,
    required ConnectedClient? Function() getClient,
    required void Function(ConnectedClient) setClient,
    required SessionCipher? Function() getPendingCipher,
    required void Function(SessionCipher?) setPendingCipher,
  }) async {
    Map<String, dynamic> msg;
    try {
      final raw = jsonDecode(data) as Map<String, dynamic>;
      final cipher = getPendingCipher() ?? getClient()?.cipher;
      if (cipher != null && raw['type'] == 'encrypted') {
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

    // WS auth — mandatory first message in server mode
    if (!authenticated()) {
      if (type != 'auth') { ws.close(4401, 'Unauthorized'); return; }
      final token = msg['token'] as String? ?? '';
      if (sessions[token] != true) { ws.close(4401, 'Token inválido'); return; }
      setAuthenticated(true);
      send(ws, {'type': 'auth_ok'});
      return;
    }

    // JSON signaling
    switch (type) {
      case 'auth':
        if (!isServerMode()) {
          send(ws, {'type': 'auth_ok'});
        }

      case 'key-exchange':
        final clientPubKeyB64 = msg['publicKey'] as String? ?? '';
        if (clientPubKeyB64.isEmpty) return;
        try {
          final result = await CryptoService.serverKeyExchange(clientPubKeyB64);
          setPendingCipher(result.cipher);
          final c = getClient();
          if (c != null) c.cipher = result.cipher;
          send(ws, {'type': 'key-exchange', 'publicKey': result.serverPublicKey});
          AppLogger.instance.debug('relay_ws_handler: key exchange completo para $clientId');
        } catch (e, st) {
          AppLogger.instance.error('relay_ws_handler: key exchange fallido', error: e, stack: st);
        }

      case 'hello':
        final newClient = ConnectedClient(
          ws: ws,
          clientId: clientId,
          appName: (msg['appName'] as String?) ?? 'Unknown',
          receiving: false,
          ip: clientIp,
          deviceType: msg['deviceType'] == 'mobile' ? 'mobile' : 'desktop',
          isOwner: isLocalhost,
          cipher: getPendingCipher(),
        );
        setClient(newClient);
        clients[clientId] = newClient;
        debugPrint('[Relay] hello: ${newClient.appName}($clientId) registrado (encrypted=${newClient.cipher != null}). Total: ${clients.length}');
        send(ws, {'type': 'welcome', 'clientId': clientId}, newClient.cipher);
        broadcastClients();

      case 'set-receiving':
        final c = getClient();
        if (c == null) return;
        c.receiving = msg['receiving'] == true;
        broadcastClients();

      case 'rename':
        final c = getClient();
        if (c == null) return;
        final newName = ((msg['newName'] as String?) ?? '').trim();
        if (newName.isNotEmpty) {
          c.appName = newName;
          broadcastClients();
        }

      case 'send-request':
        final c = getClient();
        if (c == null) return;
        final to = msg['to'] as String?;
        final fileName = msg['fileName'] as String?;
        final fileSize = (msg['fileSize'] as num?)?.toInt();
        final mimeType = msg['mimeType'] as String?;
        final transferId = msg['transferId'] as String?;
        if (to == null || transferId == null) return;
        final receiver = clients[to];
        if (receiver == null) {
          send(ws, {'type': 'send-reject', 'transferId': transferId, 'reason': 'offline'}, c.cipher);
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
        }, receiver.cipher);

      case 'send-accept':
        final transferId = msg['transferId'] as String?;
        if (transferId == null) return;
        final session = transfers[transferId];
        if (session == null || session.receiverClientId != clientId) return;
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
          send(sender.ws, {'type': 'send-reject', 'transferId': transferId}, sender.cipher);
        }
        transfers.remove(transferId);

      case 'send-cancel':
        final transferId = msg['transferId'] as String?;
        if (transferId == null) return;
        final session = transfers[transferId];
        if (session == null) return;
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
          send(receiver.ws, {'type': 'send-complete', 'transferId': transferId}, receiver.cipher);
        }
        transfers.remove(transferId);
    }
  }

  // ─── Binary relay ────────────────────────────────────────────────

  Future<void> _relayBinaryFrame(Uint8List buf, SessionCipher? senderCipher) async {
    Uint8List payload;
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

    if (payload.length <= 36) return;
    final transferId = utf8.decode(payload.sublist(0, 36)).trim();
    final session = transfers[transferId];
    if (session == null) return;
    final receiver = clients[session.receiverClientId];
    if (receiver == null) return;

    if (receiver.cipher != null) {
      try {
        final encrypted = await receiver.cipher!.encryptBinary(payload);
        receiver.ws.add(encrypted);
      } catch (e) {
        AppLogger.instance.error('relay_ws_handler: fallo al cifrar chunk para receptor', error: e);
      }
    } else {
      try { receiver.ws.add(payload); } catch (_) {}
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  void send(WebSocket ws, Map<String, dynamic> msg, [SessionCipher? cipher]) {
    if (cipher == null) {
      try { ws.add(jsonEncode(msg)); } catch (_) {}
      return;
    }
    unawaited(_sendEncrypted(ws, msg, cipher));
  }

  Future<void> _sendEncrypted(WebSocket ws, Map<String, dynamic> msg, SessionCipher cipher) async {
    try {
      final encrypted = await cipher.encryptJson(jsonEncode(msg));
      ws.add(jsonEncode({'type': 'encrypted', ...encrypted}));
    } catch (_) {}
  }
}
