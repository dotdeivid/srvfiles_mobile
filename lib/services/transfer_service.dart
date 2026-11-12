import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../config/api_config.dart';
import '../models/transfer_client.dart';
import '../models/transfer_request.dart';
import 'app_logger.dart';
import 'crypto_service.dart';
import 'e2e_service.dart';

/// Tamaño de chunk: 256 KB — mismo que el frontend web.
const int chunkSize = 256 * 1024;

/// Largo del header de transferId en bytes.
const int transferIdLength = 36;

/// Se lanza desde [TransferService.sendFile] cuando la transferencia se canceló
/// o la conexión se cerró antes de terminar.
class TransferAbortedException implements Exception {
  final String reason;
  const TransferAbortedException(this.reason);
  @override
  String toString() => 'TransferAbortedException: $reason';
}

/// Token de cancelación compartido entre quien inicia un envío y el bucle
/// que manda los chunks.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Maneja la conexión WebSocket para transferencias P2P.
/// Replica la lógica de transfer.api.ts del frontend web.
///
/// - Los mensajes entrantes se procesan en orden (cola), para que un
///   `send-complete` nunca se adelante a los últimos chunks.
/// - Los salientes pasan por un único `StreamController` conectado al socket
///   con `addStream`, lo que da contrapresión: [sendFile] espera cuando el
///   buffer del socket está lleno en lugar de encolar el archivo entero.
/// - Con `autoReconnect`, reconecta con backoff tras un corte.
class TransferService {
  WebSocket? _ws;
  StreamController<Object>? _out;
  Completer<void>? _writable; // no nulo mientras el socket está saturado
  StreamSubscription? _subscription;
  String? _clientId;
  ApiConfig? _config;

  // ─── Callbacks de eventos ────────────────────────────────────────
  void Function()? onAuthOk;
  void Function(String clientId)? onWelcome;
  void Function(List<TransferClient> clients)? onClientsUpdate;
  void Function(IncomingTransferRequest request)? onSendRequest;
  void Function(String transferId)? onSendAccept;
  void Function(String transferId, String? reason)? onSendReject;
  void Function(String transferId)? onSendCancel;
  /// [finalMarker]: marcador E2E cifrado (e2e.final) que manda el emisor.
  void Function(String transferId, String? finalMarker)? onSendComplete;

  /// Clave pública E2E del receptor (solo le llega al emisor).
  void Function(String transferId, String publicKey)? onSendKey;
  void Function(String transferId, Uint8List data)? onBinaryChunk;
  void Function()? onDisconnected;
  void Function()? onFilesChanged;

  bool _disposed = false;
  bool _connected = false;
  bool _sessionStarted = false;

  /// Se incrementa en cada conexión para descartar eventos de sockets viejos.
  int _generation = 0;

  // Reconexión
  bool _autoReconnect = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const _backoff = [1, 2, 5, 10, 20, 30];

  String? get clientId => _clientId;

  /// true mientras el socket está abierto.
  bool get isConnected => _connected && !_disposed;

  /// true si la sesión actual negoció cifrado con el servidor/relay.
  bool get isEncrypted => _cipher != null;

  // ─── Session token (para servidores con PIN) ──────────────────────
  String? _sessionToken;
  void Function()? onAuthRequired; // se dispara si el WS cierra con 4401

  /// Guarda el token obtenido vía POST /api/auth.
  void setToken(String token) => _sessionToken = token;

  /// Limpia el token de sesión.
  void clearToken() => _sessionToken = null;

  /// Devuelve true si hay un token de sesión activo.
  bool get hasToken => _sessionToken != null;

  // ─── Cifrado (ECDH P-256 + AES-256-GCM) ──────────────────────────
  SessionCipher? _cipher;
  Completer<String>? _keyExchangeCompleter;

  /// Cola de envíos cifrados para preservar el orden de mensajes.
  Future<void> _sendQueue = Future.value();

  /// Cola de procesamiento de mensajes entrantes.
  Future<void> _receiveQueue = Future.value();

  /// Conecta al WebSocket del servidor.
  ///
  /// Con [autoReconnect] vuelve a conectar con backoff si la conexión se
  /// pierde (salvo cierre por autenticación o [dispose]).
  void connect(ApiConfig config, {bool autoReconnect = false}) {
    _config = config;
    _autoReconnect = autoReconnect;
    _disposed = false;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    unawaited(_open());
  }

  Future<void> _open() async {
    final config = _config;
    if (config == null || _disposed) return;

    _closeSocket();
    final generation = ++_generation;
    _cipher = null;
    _keyExchangeCompleter = null;
    _sessionStarted = false;
    _sendQueue = Future.value();
    _receiveQueue = Future.value();

    // El controller se crea antes de abrir el socket: lo que se envíe mientras
    // conecta queda en buffer y sale en orden al abrirse.
    // Se cierra en _handleClosed / _closeSocket.
    // ignore: close_sinks
    final out = StreamController<Object>(
      onPause: () => _writable ??= Completer<void>(),
      onResume: _markWritable,
    );
    _out = out;

    // Autenticarse primero. Sin token se manda un auth vacío: el relay sin PIN
    // responde auth_ok y un servidor protegido cierra con 4401 (pedir PIN).
    out.add(jsonEncode({'type': 'auth', 'token': _sessionToken ?? ''}));

    WebSocket ws;
    try {
      ws = await WebSocket.connect(config.wsUrl)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (generation != _generation || _disposed) return;
      AppLogger.instance.warn('transfer_service.dart: no se pudo conectar a ${config.wsUrl}: $e');
      _handleClosed(generation, null);
      return;
    }

    if (generation != _generation || _disposed) {
      unawaited(ws.close());
      return;
    }

    // Detecta conexiones muertas (wifi perdido) sin esperar al timeout de TCP.
    ws.pingInterval = const Duration(seconds: 15);
    _ws = ws;
    _connected = true;

    unawaited(ws.addStream(out.stream).then((_) {
      return ws.close().catchError((_) {});
    }).catchError((Object e) {
      AppLogger.instance.debug('transfer_service.dart: addStream terminó: $e');
    }));

    _subscription = ws.listen(
      (data) {
        if (generation != _generation) return;
        _receiveQueue = _receiveQueue
            .then((_) => _onMessage(data))
            .catchError((Object e, StackTrace st) {
          AppLogger.instance.error('transfer_service.dart: error procesando mensaje', error: e, stack: st);
        });
      },
      onDone: () => _handleClosed(generation, ws.closeCode),
      onError: (Object e) {
        AppLogger.instance.warn('transfer_service.dart: error en WebSocket: $e');
        _handleClosed(generation, ws.closeCode);
      },
      cancelOnError: true,
    );
  }

  void _markWritable() {
    final c = _writable;
    _writable = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _handleClosed(int generation, int? closeCode) {
    if (generation != _generation) return;
    final wasConnected = _connected;
    _connected = false;
    _ws = null;
    _clientId = null;
    _cipher = null;
    _markWritable(); // libera a sendFile, que verá la conexión cerrada
    _out?.close();
    _out = null;
    if (_disposed) return;

    if (closeCode == 4401) {
      _autoReconnect = false;
      onAuthRequired?.call();
      return;
    }
    if (wasConnected) onDisconnected?.call();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_autoReconnect || _disposed) return;
    _reconnectTimer?.cancel();
    final seconds = _backoff[_reconnectAttempt.clamp(0, _backoff.length - 1)];
    _reconnectAttempt++;
    AppLogger.instance.info('transfer_service.dart: reconectando en ${seconds}s (intento $_reconnectAttempt)');
    _reconnectTimer = Timer(Duration(seconds: seconds), () => unawaited(_open()));
  }

  /// Fuerza un intento de reconexión inmediato (p. ej. al volver a la app).
  void reconnectNow() {
    if (_disposed || _config == null || isConnected) return;
    _reconnectTimer?.cancel();
    unawaited(_open());
  }

  Future<void> _onMessage(dynamic message) async {
    if (message is Uint8List) {
      await _handleBinary(message);
    } else if (message is List<int>) {
      await _handleBinary(Uint8List.fromList(message));
    } else if (message is String) {
      await _handleJson(message);
    }
  }

  Future<void> _handleBinary(Uint8List data) async {
    final cipher = _cipher;
    if (cipher != null) {
      try {
        data = await cipher.decryptBinary(data);
      } catch (e, st) {
        AppLogger.instance.error('transfer_service.dart: binary decryption failed', error: e, stack: st);
        return;
      }
    }
    if (data.length <= transferIdLength) return;
    final transferId = utf8.decode(data.sublist(0, transferIdLength)).trim();
    final chunkData = Uint8List.sublistView(data, transferIdLength);
    onBinaryChunk?.call(transferId, chunkData);
  }

  Future<void> _handleJson(String text) async {
    try {
      var msg = jsonDecode(text) as Map<String, dynamic>;

      final cipher = _cipher;
      if (cipher != null) {
        if (msg['type'] != 'encrypted') {
          // Con clave establecida no se aceptan mensajes en claro.
          AppLogger.instance.warn('transfer_service.dart: mensaje sin cifrar descartado (${msg['type']})');
          return;
        }
        final decrypted = await cipher.decryptJson(
          msg['iv'] as String,
          msg['data'] as String,
        );
        msg = jsonDecode(decrypted) as Map<String, dynamic>;
      }

      final type = msg['type'] as String?;
      AppLogger.instance.debug('[TransferService] ← $type');

      switch (type) {
        case 'auth_ok':
          if (_sessionStarted) return; // auth_ok duplicado
          _sessionStarted = true;
          _reconnectAttempt = 0;
          // No se espera aquí: la respuesta del key-exchange llega por esta
          // misma cola y esperarla dentro produciría un bloqueo.
          unawaited(_startSession());

        case 'key-exchange':
          final pubKey = msg['publicKey'] as String?;
          if (pubKey != null) {
            _keyExchangeCompleter?.complete(pubKey);
            _keyExchangeCompleter = null;
          }

        case 'key-exchange-error':
          _keyExchangeCompleter?.complete('');
          _keyExchangeCompleter = null;

        case 'welcome':
          _clientId = msg['clientId'] as String?;
          if (_clientId != null) onWelcome?.call(_clientId!);

        case 'clients':
          final list = ((msg['clients'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(TransferClient.fromJson)
              .where((c) => c.clientId.isNotEmpty)
              .toList();
          onClientsUpdate?.call(list);

        case 'send-request':
          final request = IncomingTransferRequest.fromJson(msg);
          if (request.transferId.isEmpty) return;
          onSendRequest?.call(request);

        case 'send-accept':
          final id = msg['transferId'] as String?;
          if (id != null) onSendAccept?.call(id);

        case 'send-reject':
          final id = msg['transferId'] as String?;
          if (id != null) onSendReject?.call(id, msg['reason'] as String?);

        case 'send-cancel':
          final id = msg['transferId'] as String?;
          if (id != null) onSendCancel?.call(id);

        case 'send-key':
          final id = msg['transferId'] as String?;
          final key = msg['publicKey'] as String?;
          if (id != null && key != null) onSendKey?.call(id, key);

        case 'send-complete':
          final id = msg['transferId'] as String?;
          final finalMarker = (msg['e2e'] as Map?)?['final'] as String?;
          if (id != null) onSendComplete?.call(id, finalMarker);

        case 'files-changed':
          onFilesChanged?.call();
      }
    } catch (e, st) {
      AppLogger.instance.error('transfer_service.dart: error procesando mensaje WS', error: e, stack: st);
    }
  }

  // ─── Key exchange ─────────────────────────────────────────────────

  Future<void> _startSession() async {
    final generation = _generation;
    await _doKeyExchange();
    if (generation != _generation || _disposed) return;
    onAuthOk?.call();
  }

  Future<void> _doKeyExchange() async {
    try {
      final cipher = await CryptoService.clientKeyExchange(
        sendPublicKey: (pubKeyB64) {
          _rawSend(jsonEncode({'type': 'key-exchange', 'publicKey': pubKeyB64}));
          AppLogger.instance.debug('transfer_service.dart: key-exchange enviado, esperando respuesta');
        },
        waitForPeerKey: () async {
          _keyExchangeCompleter = Completer<String>();
          return _keyExchangeCompleter!.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              AppLogger.instance.warn('transfer_service.dart: key exchange timeout — sin cifrado');
              _keyExchangeCompleter = null;
              return '';
            },
          );
        },
      );
      _cipher = cipher;
      if (cipher != null) {
        AppLogger.instance.info('transfer_service.dart: key exchange completo — cifrado activo');
      } else {
        AppLogger.instance.warn('transfer_service.dart: sesión sin cifrar');
      }
    } catch (e, st) {
      AppLogger.instance.error('transfer_service.dart: key exchange fallido', error: e, stack: st);
    }
  }

  // ─── Métodos de envío ─────────────────────────────────────────────

  void _rawSend(Object data) {
    final out = _out;
    if (out == null || out.isClosed) {
      AppLogger.instance.debug('transfer_service.dart: envío descartado (sin conexión)');
      return;
    }
    out.add(data);
  }

  /// Envía JSON, cifrando si el cifrado está activo. Preserva el orden mediante cola.
  void _sendJson(Map<String, dynamic> msg) {
    final cipher = _cipher;
    final payload = jsonEncode(msg);
    _sendQueue = _sendQueue.then((_) async {
      if (cipher == null) {
        _rawSend(payload);
        return;
      }
      try {
        final encrypted = await cipher.encryptJson(payload);
        _rawSend(jsonEncode({
          'type': 'encrypted',
          'iv': encrypted['iv'],
          'data': encrypted['data'],
        }));
      } catch (e) {
        // Nunca caer a texto plano con cifrado activo.
        AppLogger.instance.error('transfer_service.dart: fallo al cifrar mensaje JSON', error: e);
      }
    });
  }

  /// Registra este cliente en el servidor con un nombre.
  /// `e2e: 1` anuncia que este cliente cifra de extremo a extremo (protocolo v2).
  void register(String appName) {
    _sendJson({'type': 'hello', 'appName': appName, 'deviceType': 'mobile', 'e2e': 1});
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
    required String e2ePublicKey,
  }) {
    _sendJson({
      'type': 'send-request',
      'to': to,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'transferId': transferId,
      'e2e': {'publicKey': e2ePublicKey},
    });
  }

  /// Receptor → emisor: clave pública E2E del receptor.
  void sendKey(String transferId, String publicKey) {
    _sendJson({'type': 'send-key', 'transferId': transferId, 'publicKey': publicKey});
  }

  /// Acepta una transferencia entrante.
  void accept(String transferId) {
    _sendJson({'type': 'send-accept', 'transferId': transferId});
  }

  /// Rechaza una transferencia entrante.
  void reject(String transferId, {String? reason}) {
    _sendJson({
      'type': 'send-reject',
      'transferId': transferId,
      'reason': ?reason,
    });
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

  /// Envía [file] en chunks de 256 KB, cada uno cifrado de extremo a extremo
  /// con su índice ([e2e]) y además con la clave del canal si la hay.
  ///
  /// Lee el archivo en streaming y espera cuando el socket está saturado, así
  /// que la memoria usada no depende del tamaño del archivo. Al final manda
  /// `send-complete` con el marcador final cifrado. Lanza
  /// [TransferAbortedException] si [cancelToken] se cancela o la conexión se
  /// cierra a mitad de envío; en ese caso no se envía `send-complete`.
  Future<void> sendFile({
    required String transferId,
    required File file,
    required E2ESession e2e,
    String? fileName,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    final idBytes = Uint8List.fromList(
      utf8.encode(transferId.padRight(transferIdLength).substring(0, transferIdLength)),
    );
    final total = await file.length();
    final generation = _generation;
    var sent = 0;
    var index = 0;

    void checkAlive() {
      if (cancelToken?.isCancelled ?? false) {
        throw const TransferAbortedException('cancelled');
      }
      if (!isConnected || generation != _generation) {
        throw const TransferAbortedException('disconnected');
      }
    }

    final raf = await file.open();
    try {
      final buffer = Uint8List(chunkSize);
      while (sent < total) {
        checkAlive();
        // Esperar a que el socket acepte más datos (contrapresión).
        final writable = _writable;
        if (writable != null) await writable.future;
        checkAlive();

        final read = await raf.readInto(buffer);
        if (read <= 0) break;

        final sealed = await e2e.encryptChunk(index, Uint8List.sublistView(buffer, 0, read));
        index++;

        // Frame: [transferId en claro para que el relay enrute][chunk cifrado E2E]
        final frame = Uint8List(transferIdLength + sealed.length);
        frame.setRange(0, transferIdLength, idBytes);
        frame.setRange(transferIdLength, frame.length, sealed);

        // Esperar a que salgan los JSON pendientes para no desordenar.
        await _sendQueue;
        final cipher = _cipher;
        _rawSend(cipher != null ? await cipher.encryptBinary(frame) : frame);

        sent += read;
        onProgress?.call(total == 0 ? 1 : sent / total);
      }
    } finally {
      await raf.close();
    }

    checkAlive();
    final finalMarker = await e2e.encryptFinal(
      chunks: index,
      size: total,
      name: fileName ?? file.uri.pathSegments.last,
    );
    _sendJson({'type': 'send-complete', 'transferId': transferId, 'e2e': {'final': finalMarker}});
  }

  void _closeSocket() {
    _subscription?.cancel();
    _subscription = null;
    final out = _out;
    _out = null;
    final ws = _ws;
    _ws = null;
    _connected = false;
    _markWritable();
    if (out != null && !out.isClosed) {
      unawaited(out.close().catchError((_) {}));
    } else if (ws != null) {
      unawaited(ws.close().catchError((_) {}));
    }
  }

  /// Cierra la conexión WebSocket y detiene la reconexión.
  void dispose() {
    _disposed = true;
    _generation++;
    _reconnectTimer?.cancel();
    _closeSocket();
    _clientId = null;
    _cipher = null;
    _keyExchangeCompleter = null;
  }
}
