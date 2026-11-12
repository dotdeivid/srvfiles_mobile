import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../services/embedded_relay.dart';
import '../../services/discovery_service.dart';
import '../../services/direct_transfer_pool.dart';
import '../../services/files_service.dart';
import '../../services/transfer_service.dart';
import '../../services/app_logger.dart';

/// Manages the embedded relay lifecycle, server mode toggle, and direct-mode
/// device scanning / pool connections.
class ServerController extends ChangeNotifier {
  ServerController({
    EmbeddedRelay? relay,
    required this.directPool,
    DiscoveryService? discovery,
  })  : relay = relay ?? EmbeddedRelay.shared,
        _discovery = discovery ?? DiscoveryService();

  /// Relay de la app. Por defecto la instancia compartida, que sobrevive a los
  /// cambios de pantalla.
  final EmbeddedRelay relay;
  final DirectTransferPool directPool;
  final DiscoveryService _discovery;

  // ─── Public state ────────────────────────────────────────────────

  List<DiscoveredServer> directDevices = [];
  bool directScanning = false;

  // ─── Internal ────────────────────────────────────────────────────

  Timer? _scanTimer;
  bool _scanPaused = false;
  bool _disposed = false;

  /// Intervalo entre barridos automáticos de la red en modo directo.
  static const scanInterval = Duration(seconds: 30);

  bool get isDirectMode => !relay.isServerMode;

  // ─── Relay lifecycle ────────────────────────────────────────────

  /// Starts the embedded relay. Returns the relay URL on success, null on error.
  Future<String?> startRelay() async {
    AppLogger.instance.info('[ServerCtrl] starting embedded relay');
    try {
      await relay.start();
      AppLogger.instance.info('[ServerCtrl] relay started: ${relay.url}');
      return relay.url;
    } catch (e) {
      AppLogger.instance.error('[ServerCtrl] relay start failed', error: e);
      _notify();
      return null;
    }
  }

  /// Activates server mode on the relay. Returns the PIN on success, null if
  /// the user cancelled.
  ///
  /// [checkWarning] — called to check if the server-mode warning dialog was
  /// dismissed. Should return `true` to proceed or `false` to cancel.
  ///
  /// La propia app recibe un token directamente del relay (sin HTTP) y lo
  /// guarda en [transferService] y en el FilesService local.
  Future<String?> activateServerMode({
    required Future<bool> Function() checkWarning,
    required TransferService transferService,
    required void Function(FilesService, ApiConfig) setFilesService,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('server_mode_warning_dismissed') ?? false;

    if (!dismissed) {
      final confirmed = await checkWarning();
      if (!confirmed) return null;
    }

    AppLogger.instance.info('[ServerCtrl] activating server mode');
    try {
      stopDirectScanning();
      directPool.disposeAll();
      final pin = await relay.startServerMode();

      final token = relay.issueLocalToken();
      transferService.setToken(token);

      final localConfig = ApiConfig(relay.loopbackUrl);
      final localFilesService = FilesService(localConfig)..setToken(token);
      setFilesService(localFilesService, localConfig);
      AppLogger.instance.info('[ServerCtrl] server mode active');
      _notify();
      return pin;
    } catch (e) {
      AppLogger.instance.error('[ServerCtrl] activateServerMode error', error: e);
      rethrow;
    }
  }

  // ─── Auto-auth with local relay ────────────────────────────────

  /// Renueva el token de la app contra su propio relay (p. ej. si caducó).
  bool autoAuthWithRelay(TransferService transferService, FilesService? filesService) {
    if (!relay.isServerMode) return false;
    final token = relay.issueLocalToken();
    transferService.setToken(token);
    filesService?.setToken(token);
    AppLogger.instance.info('[ServerCtrl] auto-auth with relay OK');
    return true;
  }

  // ─── Direct mode scanning ──────────────────────────────────────

  void startDirectScanning() {
    _scanTimer?.cancel();
    unawaited(scanForDirectDevices());
    _scanTimer = Timer.periodic(scanInterval, (_) {
      if (!_scanPaused) unawaited(scanForDirectDevices());
    });
  }

  void stopDirectScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    directDevices = [];
    _notify();
  }

  /// Pausa el barrido periódico (app en segundo plano).
  void pauseScanning() => _scanPaused = true;

  /// Reanuda el barrido y escanea enseguida si estaba en modo directo.
  void resumeScanning() {
    final wasPaused = _scanPaused;
    _scanPaused = false;
    if (wasPaused && _scanTimer != null) unawaited(scanForDirectDevices());
  }

  Future<void> scanForDirectDevices() async {
    if (directScanning || _disposed) return; // evitar barridos solapados
    directScanning = true;
    _notify();
    try {
      final devices = await _discovery.scanLan(isCancelled: () => _disposed);
      final ownIp = relay.localIp;
      // Solo teléfonos con relay y sin PIN aceptan envío directo.
      directDevices = devices
          .where((d) => d.acceptsDirectTransfer && d.ip != ownIp)
          .toList();
    } catch (e) {
      AppLogger.instance.warn('[ServerCtrl] scan failed: $e');
    } finally {
      directScanning = false;
      _notify();
    }
  }

  /// Get a pool connection to a direct device. Returns null on failure.
  Future<DirectPeerConnection?> getDirectConnection(String url, String deviceName) async {
    return directPool.getConnection(url, deviceName);
  }

  void touchPool(String url) => directPool.touch(url);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ─── Cleanup ────────────────────────────────────────────────────

  /// Detiene el escaneo y el pool. El relay compartido sigue vivo, pero el
  /// modo servidor se apaga al salir de la pantalla que lo activó.
  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    directPool.disposeAll();
    if (relay.isServerMode) unawaited(relay.stopServerMode());
    super.dispose();
  }
}
