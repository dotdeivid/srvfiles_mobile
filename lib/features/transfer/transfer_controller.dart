import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/api_config.dart';
import '../../models/transfer_client.dart';
import '../../models/transfer_request.dart';
import '../../models/active_transfer.dart';
import '../../services/transfer_service.dart';
import '../../services/device_name_service.dart';
import '../../services/notification_service.dart';
import '../../services/received_files_service.dart';
import '../../services/app_logger.dart';
import '../../features/files/files_controller.dart';
import 'receive_buffer.dart';
import 'pending_send.dart';

/// Callback typedefs for UI events that need scaffolding context.
typedef ShowSnackBar = void Function(String message, {bool isError, String? actionLabel, VoidCallback? onAction});
typedef ShowIncomingDialog = Future<bool?> Function(IncomingTransferRequest request);
typedef OnAuthRequired = void Function();

/// Manages all P2P transfer state: WebSocket connection, sending, receiving,
/// chunk buffering, progress tracking, and device naming.
///
/// Replaces the transfer-related `setState()` calls and methods that lived in
/// `_HomeScreenState` (home_screen.dart L512–860).
class TransferController extends ChangeNotifier {
  TransferController({
    required this.transferService,
    required this.deviceNameService,
    required this.notificationService,
    required this.receivedFilesService,
    this.showSnackBar,
    this.showIncomingDialog,
    this.onAuthRequired,
    this.onFilesChanged,
  });

  final TransferService transferService;
  final DeviceNameService deviceNameService;
  final NotificationService notificationService;
  final ReceivedFilesService receivedFilesService;

  // UI callbacks — set by the screen that owns this controller
  ShowSnackBar? showSnackBar;
  ShowIncomingDialog? showIncomingDialog;
  OnAuthRequired? onAuthRequired;
  VoidCallback? onFilesChanged;

  // ─── Public state ────────────────────────────────────────────────

  String? myClientId;
  List<TransferClient> onlineClients = [];
  ActiveTransfer? activeTransfer;
  String deviceName = '';

  // ─── Internal state ──────────────────────────────────────────────

  final Map<String, ReceiveBuffer> _receiveBuffers = {};
  PendingSend? _pendingSend;

  /// Access pending send for cancel logic.
  PendingSend? get pendingSend => _pendingSend;

  // ─── Initialisation ─────────────────────────────────────────────

  Future<void> initTransfer() async {
    deviceName = await deviceNameService.getName();

    transferService.onWelcome = (clientId) {
      myClientId = clientId;
      notifyListeners();
    };

    transferService.onClientsUpdate = (clients) {
      onlineClients = clients;
      notifyListeners();
    };

    transferService.onSendRequest = (request) {
      AppLogger.instance.info(
        '[TransferCtrl] incoming transfer: ${request.fileName} from ${request.fromName}',
      );
      notificationService.showIncomingTransfer(request.fromName, request.fileName);
      _handleIncomingRequest(request);
    };

    transferService.onSendAccept = (transferId) => handleSendAccept(transferId);

    transferService.onSendReject = (transferId, reason) {
      if (_pendingSend?.transferId == transferId) {
        _pendingSend = null;
        activeTransfer = null;
        notifyListeners();
        showSnackBar?.call('El destinatario rechazó el envío', isError: true);
      }
    };

    transferService.onSendCancel = (transferId) {
      _receiveBuffers.remove(transferId);
      if (_pendingSend?.transferId == transferId) _pendingSend = null;
      if (activeTransfer?.transferId == transferId) {
        activeTransfer = null;
        notifyListeners();
        showSnackBar?.call('Transferencia cancelada');
      }
    };

    transferService.onSendComplete = (transferId) => _handleReceiveComplete(transferId);

    transferService.onBinaryChunk = (transferId, data) => handleBinaryChunk(transferId, data);

    transferService.onDisconnected = () {
      AppLogger.instance.warn('[TransferCtrl] WS disconnected, will reconnect in 3s');
      myClientId = null;
      onlineClients = [];
      activeTransfer = null;
      notifyListeners();
    };

    transferService.onFilesChanged = () => onFilesChanged?.call();

    transferService.onAuthRequired = () => onAuthRequired?.call();
  }

  Future<void> connectWebSocket(ApiConfig apiConfig, {
    required bool hasServer,
    required bool autoServerMode,
    required VoidCallback onAuthOk,
  }) async {
    transferService.onAuthOk = () async {
      await ensureDeviceName();
      transferService.register(deviceName);
      transferService.setReceiving(true);
      onAuthOk();
    };
    transferService.connect(apiConfig);
    if (!transferService.hasToken) {
      if (!hasServer && !autoServerMode) {
        await ensureDeviceName();
      }
      transferService.register(deviceName);
      transferService.setReceiving(true);
    }
  }

  Future<void> ensureDeviceName() async {
    deviceName = await deviceNameService.getName();
    final isFirst = await deviceNameService.isFirstLaunch();
    if (isFirst) {
      final name = deviceNameService.generateRandomName();
      await deviceNameService.saveName(name);
      deviceName = name;
    }
  }

  // ─── Send file ──────────────────────────────────────────────────

  Future<void> sendFile(String clientId, String peerName) async {
    if (activeTransfer != null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;

    final platformFile = result.files.first;
    if (platformFile.path == null) return;

    final file = File(platformFile.path!);
    final fileName = platformFile.name;
    final fileSize = await file.length();
    final transferId = FilesController.generateTransferId();

    _pendingSend = PendingSend(
      transferId: transferId,
      file: file,
      peerId: clientId,
      service: transferService,
    );

    activeTransfer = ActiveTransfer(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      progress: 0,
      direction: TransferDirection.sending,
      peerName: peerName,
      peerId: clientId,
      waiting: true,
    );
    notifyListeners();

    transferService.sendRequest(
      to: clientId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'application/octet-stream',
      transferId: transferId,
    );
  }

  /// Send via a specific service (for direct pool connections).
  Future<void> sendFileViaService({
    required String targetClientId,
    required String peerName,
    required TransferService service,
  }) async {
    if (activeTransfer != null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;

    final platformFile = result.files.first;
    if (platformFile.path == null) return;

    final file = File(platformFile.path!);
    final fileName = platformFile.name;
    final fileSize = await file.length();
    final transferId = FilesController.generateTransferId();

    _pendingSend = PendingSend(
      transferId: transferId,
      file: file,
      peerId: targetClientId,
      service: service,
    );

    activeTransfer = ActiveTransfer(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      progress: 0,
      direction: TransferDirection.sending,
      peerName: peerName,
      peerId: targetClientId,
      waiting: true,
    );
    notifyListeners();

    service.sendRequest(
      to: targetClientId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'application/octet-stream',
      transferId: transferId,
    );
  }

  Future<void> handleSendAccept(String transferId) async {
    final pending = _pendingSend;
    if (pending == null || pending.transferId != transferId) return;

    activeTransfer = activeTransfer?.copyWith(waiting: false);
    notifyListeners();

    final fileBytes = await pending.file.readAsBytes();

    await pending.service.sendFile(
      transferId: pending.transferId,
      fileBytes: fileBytes,
      onProgress: (progress) {
        activeTransfer = activeTransfer?.copyWith(
          progress: (progress * 100).round(),
        );
        notifyListeners();
      },
    );

    _pendingSend = null;
    activeTransfer = null;
    notifyListeners();
    showSnackBar?.call('Archivo enviado correctamente');
  }

  // ─── Receive ────────────────────────────────────────────────────

  Future<void> _handleIncomingRequest(IncomingTransferRequest request) async {
    final accepted = await showIncomingDialog?.call(request);
    if (accepted == true) {
      acceptTransfer(request);
    } else {
      transferService.reject(request.transferId);
    }
  }

  void acceptTransfer(IncomingTransferRequest request) {
    _receiveBuffers[request.transferId] = ReceiveBuffer(
      chunks: [],
      received: 0,
      total: request.fileSize,
      fileName: request.fileName,
      mimeType: request.mimeType,
    );

    activeTransfer = ActiveTransfer(
      transferId: request.transferId,
      fileName: request.fileName,
      fileSize: request.fileSize,
      progress: 0,
      direction: TransferDirection.receiving,
      peerName: request.fromName,
      peerId: request.from,
      waiting: false,
    );
    notifyListeners();

    transferService.accept(request.transferId);
  }

  void handleBinaryChunk(String transferId, Uint8List data) {
    final buffer = _receiveBuffers[transferId];
    if (buffer == null) return;

    buffer.chunks.add(data);
    buffer.received += data.length;

    final progress = (buffer.received / buffer.total * 100).round();
    activeTransfer = activeTransfer?.copyWith(progress: progress);
    notifyListeners();
  }

  Future<void> _handleReceiveComplete(String transferId) async {
    final buffer = _receiveBuffers.remove(transferId);
    if (buffer == null) return;

    // Assemble chunks
    final totalLength = buffer.chunks.fold<int>(0, (sum, c) => sum + c.length);
    final assembled = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in buffer.chunks) {
      assembled.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    // Save received file
    await receivedFilesService.saveFile(buffer.fileName, assembled);
    final peerName = activeTransfer?.peerName ?? 'otro dispositivo';
    notificationService.showTransferComplete(buffer.fileName, peerName);

    activeTransfer = null;
    notifyListeners();

    showSnackBar?.call(
      '"${buffer.fileName}" recibido',
      actionLabel: 'Abrir',
      onAction: () {
        // Caller should handle opening the file
      },
    );

    onFilesChanged?.call();
  }

  // ─── Cancel ─────────────────────────────────────────────────────

  void cancelTransfer() {
    final transfer = activeTransfer;
    if (transfer == null) return;

    final serviceToCancel = _pendingSend?.service ?? transferService;
    serviceToCancel.cancel(transfer.transferId);
    _receiveBuffers.remove(transfer.transferId);
    _pendingSend = null;

    activeTransfer = null;
    notifyListeners();
    showSnackBar?.call('Transferencia cancelada');
  }

  // ─── Rename ─────────────────────────────────────────────────────

  Future<void> rename(String newName) async {
    await deviceNameService.saveName(newName);
    deviceName = newName;
    transferService.rename(newName);
    notifyListeners();
  }

  // ─── Cleanup ────────────────────────────────────────────────────

  @override
  void dispose() {
    transferService.dispose();
    super.dispose();
  }
}
