import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/transfer_client.dart';
import '../models/transfer_request.dart';
import 'transfer_service.dart';
import 'app_logger.dart';

/// Conexión activa a un relay remoto con el clientId del dueño del relay resuelto.
class DirectPeerConnection {
  final TransferService service;
  final String targetClientId;
  const DirectPeerConnection({required this.service, required this.targetClientId});
}

/// Pool de conexiones WebSocket a relays remotos para envío directo.
///
/// Reutiliza conexiones existentes y las cierra después de [_inactivityTimeout]
/// sin actividad para no mantener WS abiertos innecesariamente.
class DirectTransferPool {
  final Map<String, _PoolEntry> _pool = {};

  static const _inactivityTimeout = Duration(seconds: 60);

  // ─── Callbacks de eventos (delegados al HomeScreen) ──────────────────
  void Function(IncomingTransferRequest)? onSendRequest;
  void Function(String transferId)? onSendAccept;
  void Function(String transferId, String? reason)? onSendReject;
  void Function(String transferId)? onSendCancel;
  void Function(String transferId)? onSendComplete;
  void Function(String transferId, Uint8List data)? onBinaryChunk;

  /// Devuelve una conexión activa al relay remoto en [targetUrl].
  ///
  /// Si ya existe una conexión válida la reutiliza (reiniciando el timer).
  /// Si no, abre una nueva, registra el dispositivo y espera a que el relay
  /// devuelva el clientId del dueño del relay (timeout 5s).
  /// Devuelve null si no se pudo establecer la conexión o resolver el clientId.
  Future<DirectPeerConnection?> getConnection(
    String targetUrl,
    String deviceName,
  ) async {
    final existing = _pool[targetUrl];
    if (existing != null && existing.service.isConnected) {
      existing.resetTimer();
      return DirectPeerConnection(
        service: existing.service,
        targetClientId: existing.targetClientId,
      );
    }

    // Eliminar entrada stale si la había
    existing?.dispose();
    _pool.remove(targetUrl);

    AppLogger.instance.info('[DirectTransferPool] opening new connection to $targetUrl');
    final service = TransferService();
    final completer = Completer<String?>();
    String? myClientId;

    service.onWelcome = (id) {
      myClientId = id;
    };

    service.onClientsUpdate = (clients) {
      if (completer.isCompleted || myClientId == null) return;
      final target = _findRelayOwner(clients, myClientId);
      if (target != null) completer.complete(target.clientId);
    };

    // Delegar eventos de transferencia al HomeScreen
    service.onSendRequest = (req) => onSendRequest?.call(req);
    service.onSendAccept = (id) => onSendAccept?.call(id);
    service.onSendReject = (id, r) => onSendReject?.call(id, r);
    service.onSendCancel = (id) => onSendCancel?.call(id);
    service.onSendComplete = (id) => onSendComplete?.call(id);
    service.onBinaryChunk = (id, data) => onBinaryChunk?.call(id, data);
    service.onDisconnected = () => _close(targetUrl);

    // En relay-only mode el relay envía auth_ok inmediatamente
    service.onAuthOk = () {
      service.register(deviceName);
      service.setReceiving(true);
    };

    service.connect(ApiConfig(targetUrl));

    String? targetClientId;
    try {
      targetClientId = await completer.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      AppLogger.instance.error('[DirectTransferPool] connection timeout or error', error: e);
    }

    if (targetClientId == null) {
      AppLogger.instance.warn('[DirectTransferPool] could not resolve relay owner for $targetUrl');
      service.dispose();
      return null;
    }

    AppLogger.instance.info('[DirectTransferPool] connection established', );

    final entry = _PoolEntry(
      service: service,
      targetClientId: targetClientId,
      onTimeout: () => _close(targetUrl),
    );
    _pool[targetUrl] = entry;

    return DirectPeerConnection(service: service, targetClientId: targetClientId);
  }

  /// Reinicia el timer de inactividad de una conexión (llamar después de una transferencia).
  void touch(String targetUrl) => _pool[targetUrl]?.resetTimer();

  void _close(String targetUrl) {
    AppLogger.instance.info('[DirectTransferPool] closing connection to $targetUrl');
    _pool.remove(targetUrl)?.dispose();
  }

  /// Cierra todas las conexiones del pool.
  void disposeAll() {
    for (final e in _pool.values) {
      e.dispose();
    }
    _pool.clear();
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────

/// Busca el dueño del relay: primero el marcado como isOwner, luego cualquier
/// cliente que no sea yo mismo.
TransferClient? _findRelayOwner(List<TransferClient> clients, String? myId) {
  for (final c in clients) {
    if (c.isOwner && c.clientId != myId) return c;
  }
  for (final c in clients) {
    if (c.clientId != myId) return c;
  }
  return null;
}

// ─── Pool entry ───────────────────────────────────────────────────────────

class _PoolEntry {
  final TransferService service;
  final String targetClientId;
  Timer? _timer;
  final VoidCallback onTimeout;

  _PoolEntry({
    required this.service,
    required this.targetClientId,
    required this.onTimeout,
  }) {
    resetTimer();
  }

  void resetTimer() {
    _timer?.cancel();
    _timer = Timer(DirectTransferPool._inactivityTimeout, onTimeout);
  }

  void dispose() {
    _timer?.cancel();
    service.dispose();
  }
}
