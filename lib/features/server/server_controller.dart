import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../services/embedded_relay.dart';
import '../../services/discovery_service.dart';
import '../../services/direct_transfer_pool.dart';
import '../../services/files_service.dart';
import '../../services/transfer_service.dart';
import '../../services/app_logger.dart';
import '../../models/transfer_request.dart';

/// Manages the embedded relay lifecycle, server mode toggle, and direct-mode
/// device scanning / pool connections.
///
/// Replaces the relay/server/direct-related logic that lived in
/// `_HomeScreenState` (home_screen.dart L167–370).
class ServerController extends ChangeNotifier {
  ServerController({
    required this.relay,
    required this.directPool,
  });

  final EmbeddedRelay relay;
  final DirectTransferPool directPool;

  // ─── Public state ────────────────────────────────────────────────

  List<DiscoveredServer> directDevices = [];
  bool directScanning = false;

  // ─── Internal ────────────────────────────────────────────────────

  Timer? _scanTimer;

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
      notifyListeners();
      return null;
    }
  }

  /// Activates server mode on the relay. Returns the PIN on success, null if
  /// the user cancelled or an error occurred.
  ///
  /// [checkWarning] — called to check if the server-mode warning dialog was
  /// dismissed. Should return `true` to proceed or `false` to cancel.
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
      final pin = await relay.startServerMode();

      // Auto-authenticate to the local relay
      final response = await http.post(
        Uri.parse('http://127.0.0.1:${relay.port}/api/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        transferService.setToken(token);
        AppLogger.instance.info('[ServerCtrl] server mode auth OK');

        final localConfig = ApiConfig('http://127.0.0.1:${relay.port}');
        final localFilesService = FilesService(localConfig);
        localFilesService.setToken(token);
        setFilesService(localFilesService, localConfig);
      } else {
        AppLogger.instance.warn(
          '[ServerCtrl] server mode auth failed: status ${response.statusCode}',
        );
      }

      return pin;
    } catch (e) {
      AppLogger.instance.error('[ServerCtrl] activateServerMode error', error: e);
      rethrow;
    }
  }

  // ─── Auto-auth with local relay ────────────────────────────────

  Future<bool> autoAuthWithRelay(TransferService transferService, FilesService? filesService) async {
    AppLogger.instance.debug('[ServerCtrl] autoAuthWithRelay');
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:${relay.port}/api/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': relay.currentPin}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        transferService.setToken(token);
        filesService?.setToken(token);
        AppLogger.instance.info('[ServerCtrl] auto-auth with relay OK');
        return true;
      }
      AppLogger.instance.warn(
        '[ServerCtrl] autoAuth failed: status ${response.statusCode}',
      );
      return false;
    } catch (e) {
      AppLogger.instance.error('[ServerCtrl] autoAuth error', error: e);
      return false;
    }
  }

  // ─── Direct mode scanning ──────────────────────────────────────

  void initDirectPoolCallbacks({
    required void Function(IncomingTransferRequest) onSendRequest,
    required void Function(String) onSendAccept,
    required void Function(String, String?) onSendReject,
    required void Function(String) onSendCancel,
    required void Function(String) onSendComplete,
    required void Function(String, Uint8List) onBinaryChunk,
  }) {
    directPool.onSendRequest = onSendRequest;
    directPool.onSendAccept = onSendAccept;
    directPool.onSendReject = onSendReject;
    directPool.onSendCancel = onSendCancel;
    directPool.onSendComplete = onSendComplete;
    directPool.onBinaryChunk = onBinaryChunk;
  }

  void startDirectScanning() {
    scanForDirectDevices();
    _scanTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => scanForDirectDevices(),
    );
  }

  void stopDirectScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    directDevices = [];
    notifyListeners();
  }

  Future<void> scanForDirectDevices() async {
    directScanning = true;
    notifyListeners();
    final devices = await DiscoveryService().scanLan();
    directDevices = devices;
    directScanning = false;
    notifyListeners();
  }

  /// Get a pool connection to a direct device. Returns null on failure.
  Future<DirectPeerConnection?> getDirectConnection(String url, String deviceName) async {
    return directPool.getConnection(url, deviceName);
  }

  void touchPool(String url) => directPool.touch(url);

  // ─── Cleanup ────────────────────────────────────────────────────

  @override
  void dispose() {
    _scanTimer?.cancel();
    directPool.disposeAll();
    relay.stop();
    super.dispose();
  }
}
