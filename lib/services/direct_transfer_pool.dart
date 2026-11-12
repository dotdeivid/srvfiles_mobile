import 'dart:async';
import '../config/api_config.dart';
import '../models/transfer_client.dart';
import 'transfer_service.dart';
import 'app_logger.dart';

/// Conexión activa a un relay remoto con el clientId del dueño del relay resuelto.
class DirectPeerConnection {
  final TransferService service;
  final String targetClientId;

  /// true si el dueño del relay soporta cifrado de extremo a extremo.
  final bool targetE2E;
  const DirectPeerConnection({required this.service, required this.targetClientId, this.targetE2E = false});
}

/// Pool de conexiones WebSocket a relays remotos para envío directo.
///
/// Reutiliza conexiones existentes y las cierra después de [_inactivityTimeout]
/// sin actividad para no mantener WS abiertos innecesariamente.
class DirectTransferPool {
  final Map<String, _PoolEntry> _pool = {};

  static const _inactivityTimeout = Duration(seconds: 60);

  /// Se llama con cada conexión nueva, antes de conectar, para que el dueño
  /// (TransferController) enganche los eventos de transferencia y responda
  /// por esa misma conexión.
  void Function(TransferService service)? onConnectionOpened;

  /// true si la conexión tiene una transferencia en curso: entonces no se
  /// cierra por inactividad.
  bool Function(TransferService service)? isBusy;

  /// Se llama cuando una conexión del pool se cae, para abortar sus
  /// transferencias.
  void Function(TransferService service)? onConnectionClosed;

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
        targetE2E: existing.targetE2E,
      );
    }

    // Eliminar entrada stale si la había
    existing?.dispose();
    _pool.remove(targetUrl);

    AppLogger.instance.info('[DirectTransferPool] opening new connection to $targetUrl');
    final service = TransferService();
    final completer = Completer<TransferClient?>();
    String? myClientId;

    onConnectionOpened?.call(service);

    service.onWelcome = (id) {
      myClientId = id;
    };

    service.onClientsUpdate = (clients) {
      if (completer.isCompleted || myClientId == null) return;
      final target = _findRelayOwner(clients, myClientId);
      if (target != null) completer.complete(target);
    };

    service.onDisconnected = () {
      if (!completer.isCompleted) completer.complete(null);
      onConnectionClosed?.call(service);
      _close(targetUrl);
    };

    // El relay tiene el modo servidor activo: no se puede enviar sin PIN.
    service.onAuthRequired = () {
      AppLogger.instance.warn('[DirectTransferPool] $targetUrl requires PIN');
      if (!completer.isCompleted) completer.complete(null);
    };

    // En relay-only mode el relay envía auth_ok inmediatamente
    service.onAuthOk = () {
      service.register(deviceName);
      service.setReceiving(true);
    };

    service.connect(ApiConfig(targetUrl));

    TransferClient? target;
    try {
      target = await completer.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      AppLogger.instance.warn('[DirectTransferPool] connection timeout: $e');
    }

    if (target == null) {
      AppLogger.instance.warn('[DirectTransferPool] could not resolve relay owner for $targetUrl');
      service.dispose();
      return null;
    }

    AppLogger.instance.info('[DirectTransferPool] connection established');

    final entry = _PoolEntry(
      service: service,
      targetClientId: target.clientId,
      targetE2E: target.e2e,
      onTimeout: () => _onIdle(targetUrl),
    );
    _pool[targetUrl] = entry;

    return DirectPeerConnection(service: service, targetClientId: target.clientId, targetE2E: target.e2e);
  }

  /// Reinicia el timer de inactividad de una conexión (llamar después de una transferencia).
  void touch(String targetUrl) => _pool[targetUrl]?.resetTimer();

  void _onIdle(String targetUrl) {
    final entry = _pool[targetUrl];
    if (entry == null) return;
    if (isBusy?.call(entry.service) ?? false) {
      entry.resetTimer();
      return;
    }
    _close(targetUrl);
  }

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

/// Busca el dueño del relay: el cliente marcado como isOwner (conectado desde
/// el propio teléfono). Sin fallback: ofrecer el archivo a "cualquier otro
/// cliente" podía mandarlo a un navegador ajeno.
TransferClient? _findRelayOwner(List<TransferClient> clients, String? myId) {
  for (final c in clients) {
    if (c.isOwner && c.clientId != myId) return c;
  }
  return null;
}

// ─── Pool entry ───────────────────────────────────────────────────────────

class _PoolEntry {
  final TransferService service;
  final String targetClientId;
  final bool targetE2E;
  Timer? _timer;
  final void Function() onTimeout;

  _PoolEntry({
    required this.service,
    required this.targetClientId,
    required this.targetE2E,
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
