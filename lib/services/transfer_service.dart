import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/transfer_client.dart';
import '../models/transfer_request.dart';

/// Tamaño de chunk: 256 KB — mismo que el frontend web.
const int chunkSize = 256 * 1024;

/// Largo del header de transferId en bytes.
const int transferIdLength = 36;

/// Maneja la conexión WebSocket para transferencias P2P.
/// Replica la lógica de transfer.api.ts del frontend web.
class TransferService {
  WebSocketChannel? _channel;
  String? _clientId;

  // ─── Callbacks de eventos ────────────────────────────────────────
  void Function()? onAuthOk;
  void Function(String clientId)? onWelcome;
  void Function(List<TransferClient> clients)? onClientsUpdate;
  void Function(IncomingTransferRequest request)? onSendRequest;
  void Function(String transferId)? onSendAccept;
  void Function(String transferId, String? reason)? onSendReject;
  void Function(String transferId)? onSendCancel;
  void Function(String transferId)? onSendComplete;
  void Function(String transferId, Uint8List data)? onBinaryChunk;
  void Function()? onDisconnected;
  void Function()? onFilesChanged;

  StreamSubscription? _subscription;
  bool _disposed = false;

  String? get clientId => _clientId;
  bool get isConnected => _channel != null && !_disposed;

  // ─── Session token (para servidores con PIN) ──────────────────────
  String? _sessionToken;
  void Function()? onAuthRequired; // se dispara si el WS cierra con 4401

  /// Guarda el token obtenido vía POST /api/auth.
  void setToken(String token) => _sessionToken = token;

  /// Limpia el token de sesión.
  void clearToken() => _sessionToken = null;

  /// Devuelve true si hay un token de sesión activo.
  bool get hasToken => _sessionToken != null;

  /// Conecta al WebSocket del servidor.
  /// Si hay un token disponible, lo envía como primer mensaje (auth handshake).
  /// Cierra cualquier conexión previa antes de abrir la nueva.
  void connect(ApiConfig config) {
    _subscription?.cancel();
    _channel?.sink.close();

    _disposed = false;
    final wsUrl = config.wsUrl;
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _subscription = _channel!.stream.listen(
      _onMessage,
      onDone: () {
        if (_disposed) return;
        final closeCode = _channel?.closeCode;
        if (closeCode == 4401) {
          onAuthRequired?.call();
        } else {
          onDisconnected?.call();
        }
      },
      onError: (_) {
        if (!_disposed) onDisconnected?.call();
      },
    );

    // Si tenemos token, autenticarse antes de registrar el cliente
    if (_sessionToken != null) {
      _sendJson({'type': 'auth', 'token': _sessionToken});
    }
  }

  void _onMessage(dynamic message) {
    if (message is Uint8List) {
      _handleBinary(message);
      return;
    }
    if (message is List<int>) {
      _handleBinary(Uint8List.fromList(message));
      return;
    }
    if (message is String) {
      _handleJson(message);
    }
  }

  void _handleBinary(Uint8List data) {
    if (data.length <= transferIdLength) return;
    final transferId = utf8.decode(data.sublist(0, transferIdLength)).trim();
    final chunkData = data.sublist(transferIdLength);
    onBinaryChunk?.call(transferId, chunkData);
  }

  void _handleJson(String text) {
    try {
      final msg = jsonDecode(text) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      debugPrint('[TransferService] ← $type');
      switch (type) {
        case 'auth_ok':
          // Servidor confirmó el token — ahora registramos el cliente
          onAuthOk?.call();
        case 'welcome':
          _clientId = msg['clientId'] as String;
          debugPrint('[TransferService] clientId asignado: $_clientId');
          onWelcome?.call(_clientId!);
        case 'clients':
          final list = (msg['clients'] as List<dynamic>)
              .map((e) => TransferClient.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('[TransferService] clients update: ${list.map((c) => '${c.appName}(${c.clientId})').join(', ')}');
          onClientsUpdate?.call(list);
        case 'send-request':
          debugPrint('[TransferService] send-request recibido: ${msg['fileName']} de ${msg['fromName']}');
          onSendRequest?.call(IncomingTransferRequest.fromJson(msg));
        case 'send-accept':
          onSendAccept?.call(msg['transferId'] as String);
        case 'send-reject':
          onSendReject?.call(
            msg['transferId'] as String,
            msg['reason'] as String?,
          );
        case 'send-cancel':
          onSendCancel?.call(msg['transferId'] as String);
        case 'send-complete':
          onSendComplete?.call(msg['transferId'] as String);
        case 'files-changed':
          onFilesChanged?.call();
      }
    } catch (e, st) {
      debugPrint('[TransferService] ERROR procesando mensaje: $e\n$st\nMensaje: $text');
    }
  }

  // ─── Métodos de envío (JSON) ─────────────────────────────────────

  void _sendJson(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Registra este cliente en el servidor con un nombre.
  void register(String appName) {
    _sendJson({'type': 'hello', 'appName': appName, 'deviceType': 'mobile'});
  }

  /// Notifica si este cliente está disponible para recibir archivos.
  void setReceiving(bool receiving) {
    _sendJson({'type': 'set-receiving', 'receiving': receiving});
  }

  /// Envía una solicitud de transferencia a otro peer.
  void sendRequest({
    required String to,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String transferId,
  }) {
    _sendJson({
      'type': 'send-request',
      'to': to,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'transferId': transferId,
    });
  }

  /// Acepta una transferencia entrante.
  void accept(String transferId) {
    _sendJson({'type': 'send-accept', 'transferId': transferId});
  }

  /// Rechaza una transferencia entrante.
  void reject(String transferId) {
    _sendJson({'type': 'send-reject', 'transferId': transferId});
  }

  /// Cancela una transferencia activa.
  void cancel(String transferId) {
    _sendJson({'type': 'send-cancel', 'transferId': transferId});
  }

  /// Actualiza el nombre de este cliente sin reconectar.
  void rename(String newName) {
    _sendJson({'type': 'rename', 'newName': newName});
  }

  // ─── Envío de archivo en chunks ──────────────────────────────────

  /// Envía un archivo como chunks binarios de 256 KB.
  /// Cada frame: 36 bytes (transferId) + datos del chunk.
  /// Envía `send-complete` al terminar.
  Future<void> sendFile({
    required String transferId,
    required Uint8List fileBytes,
    void Function(double progress)? onProgress,
  }) async {
    final idBytes = Uint8List.fromList(
      utf8.encode(transferId.padRight(transferIdLength).substring(0, transferIdLength)),
    );

    int offset = 0;
    final total = fileBytes.length;

    while (offset < total) {
      final end = (offset + chunkSize).clamp(0, total);
      final chunk = fileBytes.sublist(offset, end);

      // Construir frame: header(36) + data
      final frame = Uint8List(transferIdLength + chunk.length);
      frame.setRange(0, transferIdLength, idBytes);
      frame.setRange(transferIdLength, frame.length, chunk);

      _channel?.sink.add(frame);

      offset = end;
      onProgress?.call(offset / total);

      // Yield al event loop entre chunks para no bloquear el UI
      await Future.delayed(Duration.zero);
    }

    _sendJson({'type': 'send-complete', 'transferId': transferId});
  }

  /// Cierra la conexión WebSocket.
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _clientId = null;
  }
}
