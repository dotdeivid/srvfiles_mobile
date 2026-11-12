import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import '../../config/api_config.dart';
import '../../models/transfer_client.dart';
import '../../models/transfer_request.dart';
import '../../models/active_transfer.dart';
import '../../services/transfer_service.dart';
import '../../services/device_name_service.dart';
import '../../services/e2e_service.dart';
import '../../services/notification_service.dart';
import '../../services/received_files_service.dart';
import '../../services/app_logger.dart';
import '../../features/files/files_controller.dart';
import 'receive_buffer.dart';
import 'pending_send.dart';

/// Callback typedefs for UI events that need scaffolding context.
typedef ShowSnackBar = void Function(String message, {bool isError, String? actionLabel, VoidCallback? onAction});

/// Muestra el diálogo de transferencia entrante con el código de
/// verificación [sas]; el usuario solo puede aceptar confirmando que coincide.
/// Debe cerrarse solo (con null) cuando [dismissed] se completa: el emisor
/// canceló o venció el plazo.
typedef ShowIncomingDialog = Future<bool?> Function(
  IncomingTransferRequest request,
  String sas,
  Future<void> dismissed,
);
typedef OnAuthRequired = void Function();

/// Tiempo que se espera la respuesta del usuario a una solicitud entrante.
const _incomingRequestTimeout = Duration(seconds: 60);

/// Manages all P2P transfer state: WebSocket connection, sending, receiving,
/// progress tracking, and device naming.
///
/// Las transferencias pueden llegar por la conexión principal o por una
/// conexión del pool de envío directo: cada evento trae su [TransferService] y
/// las respuestas (aceptar, rechazar, cancelar) salen por ese mismo servicio.
///
/// Cifrado de extremo a extremo obligatorio: cada transferencia negocia su
/// propia clave entre emisor y receptor (e2e_service.dart). El relay nunca
/// puede descifrar el contenido.
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
    this.openFile,
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
  void Function(String path)? openFile;

  // ─── Public state ────────────────────────────────────────────────

  String? myClientId;
  List<TransferClient> onlineClients = [];
  ActiveTransfer? activeTransfer;
  String deviceName = '';

  /// true si la conexión principal está abierta.
  bool get isConnected => transferService.isConnected;

  /// true si la conexión principal negoció cifrado.
  bool get isEncrypted => transferService.isEncrypted;

  /// Archivos que esperan turno después del envío actual.
  int get queuedSends => _sendQueue.length;

  // ─── Internal state ──────────────────────────────────────────────

  final Map<String, ReceiveBuffer> _receives = {};
  PendingSend? _pendingSend;
  final List<_QueuedFile> _sendQueue = [];

  /// Solicitudes entrantes esperando que el usuario responda (de a una).
  final List<_IncomingRequest> _incoming = [];
  final Map<String, _IncomingRequest> _shown = {};
  bool _showingIncoming = false;
  bool _disposed = false;

  /// Access pending send for cancel logic.
  PendingSend? get pendingSend => _pendingSend;

  // ─── Initialisation ─────────────────────────────────────────────

  Future<void> initTransfer() async {
    deviceName = await deviceNameService.getName();

    transferService.onWelcome = (clientId) {
      myClientId = clientId;
      _notify();
    };

    transferService.onClientsUpdate = (clients) {
      onlineClients = clients;
      _notify();
    };

    transferService.onDisconnected = () {
      AppLogger.instance.warn('[TransferCtrl] WS disconnected — reconnecting');
      myClientId = null;
      onlineClients = [];
      handleConnectionClosed(transferService);
      _notify();
    };

    transferService.onFilesChanged = () => onFilesChanged?.call();

    transferService.onAuthRequired = () => onAuthRequired?.call();

    attachService(transferService);
  }

  /// Engancha los eventos de transferencia de [service] (conexión principal o
  /// del pool) a este controller.
  void attachService(TransferService service) {
    service.onSendRequest = (request) => unawaited(_onSendRequest(service, request));
    service.onSendAccept = (id) => handleSendAccept(id, service: service);
    service.onSendReject = (id, reason) => _onSendReject(service, id, reason);
    service.onSendCancel = (id) => _onSendCancel(service, id);
    service.onSendKey = (id, key) => _onSendKey(service, id, key);
    service.onSendComplete = (id, finalMarker) => _onReceiveComplete(service, id, finalMarker);
    service.onBinaryChunk = (id, data) => handleBinaryChunk(id, data, service: service);
  }

  /// true si [service] tiene una transferencia en curso.
  bool isServiceBusy(TransferService service) =>
      _pendingSend?.service == service ||
      _receives.values.any((r) => r.service == service);

  Future<void> connectWebSocket(ApiConfig apiConfig, {
    required VoidCallback onAuthOk,
  }) async {
    await ensureDeviceName();
    // Registrarse solo tras auth_ok: evita el doble hello y que un servidor
    // protegido reciba mensajes antes de autenticar.
    transferService.onAuthOk = () {
      transferService.register(deviceName);
      transferService.setReceiving(true);
      _notify();
      onAuthOk();
    };
    transferService.connect(apiConfig, autoReconnect: true);
  }

  Future<void> ensureDeviceName() async {
    deviceName = await deviceNameService.getName();
  }

  // ─── Send file ──────────────────────────────────────────────────

  /// Elige uno o varios archivos y los envía de a uno a [targetClientId] por
  /// [service] (la conexión principal si se omite).
  Future<void> sendFiles({
    required String targetClientId,
    required String peerName,
    TransferService? service,
  }) async {
    if (activeTransfer != null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final via = service ?? transferService;
    if (via == transferService) {
      final target = onlineClients.where((c) => c.clientId == targetClientId).firstOrNull;
      if (target != null && !target.e2e) {
        showSnackBar?.call('$peerName necesita actualizar SrvFiles para recibir archivos cifrados', isError: true);
        return;
      }
    }
    for (final f in result.files) {
      if (f.path == null) continue;
      _sendQueue.add(_QueuedFile(
        file: File(f.path!),
        fileName: f.name,
        peerId: targetClientId,
        peerName: peerName,
        service: via,
      ));
    }
    await _startNextSend();
  }

  /// Compatibilidad: envío por la conexión principal.
  Future<void> sendFile(String clientId, String peerName) =>
      sendFiles(targetClientId: clientId, peerName: peerName);

  Future<void> _startNextSend() async {
    if (_pendingSend != null || activeTransfer != null || _sendQueue.isEmpty) return;
    final next = _sendQueue.removeAt(0);

    int fileSize;
    try {
      fileSize = await next.file.length();
    } catch (e) {
      AppLogger.instance.error('[TransferCtrl] cannot read file to send', error: e);
      showSnackBar?.call('No se pudo leer "${next.fileName}"', isError: true);
      return _startNextSend();
    }

    final transferId = FilesController.generateTransferId();
    final keyPair = E2EKeyPair.generate();
    _pendingSend = PendingSend(
      transferId: transferId,
      file: next.file,
      fileName: next.fileName,
      peerId: next.peerId,
      service: next.service,
      keyPair: keyPair,
    );

    activeTransfer = ActiveTransfer(
      transferId: transferId,
      fileName: next.fileName,
      fileSize: fileSize,
      progress: 0,
      direction: TransferDirection.sending,
      peerName: next.peerName,
      peerId: next.peerId,
      waiting: true,
    );
    _notify();

    next.service.sendRequest(
      to: next.peerId,
      fileName: next.fileName,
      fileSize: fileSize,
      mimeType: lookupMimeType(next.fileName) ?? 'application/octet-stream',
      transferId: transferId,
      e2ePublicKey: keyPair.publicKey,
    );
  }

  /// Emisor: llegó la clave del receptor → derivar la sesión y mostrar el código.
  Future<void> _onSendKey(TransferService service, String transferId, String publicKey) async {
    final pending = _pendingSend;
    if (pending == null || pending.transferId != transferId || pending.service != service) return;
    if (pending.session != null) return;
    try {
      final session = await E2ESession.derive(
        ownPrivateKey: pending.keyPair.privateKey,
        peerPublicKey: publicKey,
        senderPublicKey: pending.keyPair.publicKey,
        receiverPublicKey: publicKey,
        transferId: transferId,
      );
      if (_pendingSend != pending) return;
      pending.session = session;
      if (activeTransfer?.transferId == transferId) {
        activeTransfer = activeTransfer!.copyWith(sas: session.sas);
        _notify();
      }
    } catch (e) {
      AppLogger.instance.warn('[TransferCtrl] invalid E2E key from receiver: $e');
      service.cancel(transferId);
      _finishSend();
      _sendQueue.clear();
      showSnackBar?.call('No se pudo establecer el cifrado con el destinatario', isError: true);
    }
  }

  Future<void> handleSendAccept(String transferId, {TransferService? service}) async {
    final pending = _pendingSend;
    if (pending == null || pending.transferId != transferId) return;
    if (service != null && pending.service != service) return;

    final session = pending.session;
    if (session == null) {
      // Aceptó sin intercambiar claves: no se envía nada sin cifrado E2E.
      pending.service.cancel(transferId);
      _finishSend();
      _sendQueue.clear();
      showSnackBar?.call('El destinatario no completó el cifrado de extremo a extremo', isError: true);
      return;
    }

    activeTransfer = activeTransfer?.copyWith(waiting: false);
    _notify();

    final fileName = pending.fileName;
    try {
      await pending.service.sendFile(
        transferId: pending.transferId,
        file: pending.file,
        e2e: session,
        fileName: fileName,
        cancelToken: pending.cancelToken,
        onProgress: (progress) => _setProgress(transferId, (progress * 100).floor()),
      );
      if (_pendingSend?.transferId != transferId) return;
      _finishSend();
      showSnackBar?.call(
        _sendQueue.isEmpty
            ? '"$fileName" enviado correctamente'
            : '"$fileName" enviado — quedan ${_sendQueue.length}',
      );
      await _startNextSend();
    } on TransferAbortedException catch (e) {
      AppLogger.instance.info('[TransferCtrl] send aborted: ${e.reason}');
      if (_pendingSend?.transferId != transferId) return; // ya se informó
      _finishSend();
      _sendQueue.clear();
      showSnackBar?.call(
        e.reason == 'disconnected'
            ? 'Se perdió la conexión: envío cancelado'
            : 'Transferencia cancelada',
        isError: e.reason == 'disconnected',
      );
    } catch (e, st) {
      AppLogger.instance.error('[TransferCtrl] send failed', error: e, stack: st);
      if (_pendingSend?.transferId != transferId) return;
      pending.service.cancel(transferId);
      _finishSend();
      _sendQueue.clear();
      showSnackBar?.call('Error al enviar "$fileName"', isError: true);
    }
  }

  void _finishSend() {
    _pendingSend = null;
    activeTransfer = null;
    _notify();
  }

  void _onSendReject(TransferService service, String transferId, String? reason) {
    final pending = _pendingSend;
    if (pending == null || pending.transferId != transferId || pending.service != service) {
      return;
    }
    pending.cancelToken.cancel();
    _finishSend();
    _sendQueue.clear();
    final message = switch (reason) {
      'offline' => 'El destinatario ya no está conectado',
      'busy' => 'El destinatario está ocupado con otra transferencia',
      'timeout' => 'El destinatario no respondió',
      'e2e-required' || 'e2e-unsupported' =>
        'El otro dispositivo necesita actualizar SrvFiles (cifrado de extremo a extremo)',
      'e2e-unavailable' => 'El otro dispositivo abrió SrvFiles sin HTTPS y no puede recibir archivos cifrados',
      _ => 'El destinatario rechazó el envío',
    };
    showSnackBar?.call(message, isError: true);
  }

  // ─── Receive ────────────────────────────────────────────────────

  Future<void> _onSendRequest(TransferService service, IncomingTransferRequest request) async {
    AppLogger.instance.info(
      '[TransferCtrl] incoming transfer: ${request.fileName} from ${request.fromName}',
    );
    if (request.senderPublicKey.isEmpty) {
      service.reject(request.transferId, reason: 'e2e-required');
      return;
    }
    // Ocupado con otra transferencia: rechazar sin molestar al usuario.
    if (activeTransfer != null || _incoming.length >= 5) {
      service.reject(request.transferId, reason: 'busy');
      return;
    }
    // La clave propia se manda enseguida: el emisor necesita el código para
    // mostrarlo mientras el usuario decide.
    final E2ESession session;
    try {
      final own = E2EKeyPair.generate();
      session = await E2ESession.derive(
        ownPrivateKey: own.privateKey,
        peerPublicKey: request.senderPublicKey,
        senderPublicKey: request.senderPublicKey,
        receiverPublicKey: own.publicKey,
        transferId: request.transferId,
      );
      service.sendKey(request.transferId, own.publicKey);
    } catch (e) {
      AppLogger.instance.warn('[TransferCtrl] invalid E2E key from sender: $e');
      service.reject(request.transferId, reason: 'e2e-required');
      return;
    }
    if (_disposed) return;
    final entry = _IncomingRequest(request, service, session);
    entry.timeout = Timer(_incomingRequestTimeout, () {
      if (_incoming.remove(entry) || !entry.answered) {
        AppLogger.instance.info('[TransferCtrl] incoming request timed out');
        entry.answered = true;
        service.reject(request.transferId, reason: 'timeout');
        entry.dismiss();
      }
    });
    _incoming.add(entry);
    unawaited(notificationService.showIncomingTransfer(request.fromName, request.fileName));
    unawaited(_showNextIncoming());
  }

  Future<void> _showNextIncoming() async {
    if (_showingIncoming || _incoming.isEmpty || _disposed) return;
    final entry = _incoming.removeAt(0);
    if (entry.answered) return _showNextIncoming();

    _showingIncoming = true;
    _shown[entry.request.transferId] = entry;
    bool? accepted;
    try {
      accepted = await showIncomingDialog?.call(entry.request, entry.session.sas, entry.dismissed.future);
    } finally {
      _showingIncoming = false;
      _shown.remove(entry.request.transferId);
    }
    entry.timeout?.cancel();
    if (!entry.answered) {
      entry.answered = true;
      if (accepted == true) {
        await acceptTransfer(entry.request, session: entry.session, service: entry.service);
      } else {
        entry.service.reject(entry.request.transferId);
      }
    }
    unawaited(_showNextIncoming());
  }

  Future<void> acceptTransfer(
    IncomingTransferRequest request, {
    required E2ESession session,
    TransferService? service,
  }) async {
    final via = service ?? transferService;
    if (activeTransfer != null) {
      via.reject(request.transferId, reason: 'busy');
      return;
    }

    ReceivedFileSink sink;
    try {
      sink = await receivedFilesService.openWrite(request.fileName);
    } catch (e, st) {
      AppLogger.instance.error('[TransferCtrl] cannot open file for receiving', error: e, stack: st);
      via.reject(request.transferId);
      showSnackBar?.call('No se pudo guardar el archivo en el dispositivo', isError: true);
      return;
    }

    _receives[request.transferId] = ReceiveBuffer(
      sink: sink,
      service: via,
      session: session,
      total: request.fileSize,
      fileName: request.fileName,
      mimeType: request.mimeType,
      peerName: request.fromName,
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
      sas: session.sas,
    );
    _notify();

    via.accept(request.transferId);
  }

  /// Chunk cifrado E2E: se descifra con el índice que le toca (orden de
  /// llegada) y se escribe; todo encadenado en [ReceiveBuffer.work].
  void handleBinaryChunk(String transferId, Uint8List data, {TransferService? service}) {
    final buffer = _receives[transferId];
    if (buffer == null || buffer.failed != null) return;
    if (service != null && buffer.service != service) return;

    final index = buffer.nextIndex++;
    final sealed = Uint8List.fromList(data);
    buffer.work = buffer.work.then((_) async {
      if (buffer.failed != null) return;
      Uint8List chunk;
      try {
        chunk = await buffer.session.decryptChunk(index, sealed);
      } catch (_) {
        buffer.failed = '"${buffer.fileName}": datos alterados o fuera de orden, se descartó';
        buffer.service.cancel(transferId);
        _abortReceive(transferId, buffer.failed!);
        return;
      }
      // Más datos de los anunciados: descartar la transferencia.
      if (buffer.received + chunk.length > buffer.total) {
        buffer.failed = 'El archivo recibido no coincide con el tamaño anunciado';
        buffer.service.cancel(transferId);
        _abortReceive(transferId, buffer.failed!);
        return;
      }
      try {
        buffer.sink.add(chunk);
      } catch (e) {
        AppLogger.instance.error('[TransferCtrl] write failed while receiving', error: e);
        buffer.failed = 'No se pudo escribir el archivo (¿sin espacio?)';
        buffer.service.cancel(transferId);
        _abortReceive(transferId, buffer.failed!);
        return;
      }
      buffer.received += chunk.length;
      if (buffer.total > 0) {
        _setProgress(transferId, (buffer.received * 100 ~/ buffer.total));
      }
    });
  }

  Future<void> _onReceiveComplete(TransferService service, String transferId, String? finalMarker) async {
    final buffer = _receives[transferId];
    if (buffer == null || buffer.service != service) return;
    await buffer.work;
    if (_receives.remove(transferId) == null || buffer.failed != null) return; // ya abortada

    // Marcador final autenticado por el emisor: cantidad de chunks, tamaño y nombre.
    var intact = false;
    try {
      final fin = await buffer.session.decryptFinal(buffer.nextIndex, finalMarker ?? '');
      intact = fin.chunks == buffer.nextIndex &&
          fin.size == buffer.received &&
          fin.size == buffer.total &&
          fin.name == buffer.fileName;
    } catch (_) {
      intact = false;
    }
    if (!intact) {
      AppLogger.instance.warn(
        '[TransferCtrl] incomplete or tampered transfer: ${buffer.received}/${buffer.total} bytes',
      );
      await buffer.sink.discard();
      _clearActive(transferId);
      showSnackBar?.call('"${buffer.fileName}" llegó incompleto o alterado y se descartó', isError: true);
      return;
    }

    String savedPath;
    try {
      savedPath = await buffer.sink.commit();
    } catch (e, st) {
      AppLogger.instance.error('[TransferCtrl] could not save received file', error: e, stack: st);
      await buffer.sink.discard();
      _clearActive(transferId);
      showSnackBar?.call('No se pudo guardar "${buffer.fileName}"', isError: true);
      return;
    }

    unawaited(notificationService.showTransferComplete(
      p.basename(savedPath),
      buffer.peerName,
      path: savedPath,
    ));
    _clearActive(transferId);

    showSnackBar?.call(
      '"${p.basename(savedPath)}" recibido',
      actionLabel: openFile != null ? 'Abrir' : null,
      onAction: openFile != null ? () => openFile!(savedPath) : null,
    );

    onFilesChanged?.call();
  }

  void _onSendCancel(TransferService service, String transferId) {
    // Solicitud que el usuario todavía no respondió.
    for (final entry in List.of(_incoming)) {
      if (entry.request.transferId == transferId && entry.service == service) {
        _incoming.remove(entry);
        entry.answered = true;
        entry.timeout?.cancel();
      }
    }
    _dismissShownIncoming(transferId, service);

    final pending = _pendingSend;
    if (pending != null && pending.transferId == transferId && pending.service == service) {
      pending.cancelToken.cancel();
      _finishSend();
      _sendQueue.clear();
      showSnackBar?.call('El destinatario canceló la transferencia');
      return;
    }

    final buffer = _receives[transferId];
    if (buffer != null && buffer.service == service) {
      _abortReceive(transferId, 'El emisor canceló la transferencia', isError: false);
    }
  }

  /// Cierra el diálogo si está mostrando la solicitud [transferId].
  void _dismissShownIncoming(String transferId, TransferService service) {
    final entry = _shown[transferId];
    if (entry != null && entry.service == service) {
      entry.answered = true;
      entry.timeout?.cancel();
      entry.dismiss();
    }
  }

  void _abortReceive(String transferId, String message, {bool isError = true}) {
    final buffer = _receives.remove(transferId);
    if (buffer != null) unawaited(buffer.sink.discard());
    _clearActive(transferId);
    showSnackBar?.call(message, isError: isError);
  }

  void _clearActive(String transferId) {
    if (activeTransfer?.transferId == transferId) {
      activeTransfer = null;
    }
    _notify();
  }

  /// Aborta las transferencias que usaban una conexión que se cerró.
  void handleConnectionClosed(TransferService service) {
    final pending = _pendingSend;
    if (pending != null && pending.service == service) {
      pending.cancelToken.cancel();
      _finishSend();
      _sendQueue.removeWhere((q) => q.service == service);
      showSnackBar?.call('Se perdió la conexión: envío cancelado', isError: true);
    }
    for (final id in _receives.entries
        .where((e) => e.value.service == service)
        .map((e) => e.key)
        .toList()) {
      _abortReceive(id, 'Se perdió la conexión: recepción cancelada');
    }
    for (final entry in List.of(_incoming)) {
      if (entry.service == service) {
        _incoming.remove(entry);
        entry.answered = true;
        entry.timeout?.cancel();
      }
    }
    for (final entry in _shown.values.where((e) => e.service == service).toList()) {
      entry.answered = true;
      entry.dismiss();
    }
  }

  // ─── Cancel ─────────────────────────────────────────────────────

  void cancelTransfer() {
    final transfer = activeTransfer;
    if (transfer == null) return;

    final pending = _pendingSend;
    if (pending != null && pending.transferId == transfer.transferId) {
      pending.cancelToken.cancel();
      pending.service.cancel(transfer.transferId);
      _sendQueue.clear();
      _finishSend();
    } else {
      final buffer = _receives.remove(transfer.transferId);
      (buffer?.service ?? transferService).cancel(transfer.transferId);
      if (buffer != null) unawaited(buffer.sink.discard());
      activeTransfer = null;
      _notify();
    }
    showSnackBar?.call('Transferencia cancelada');
  }

  // ─── Rename ─────────────────────────────────────────────────────

  Future<void> rename(String newName) async {
    deviceName = await deviceNameService.saveName(newName);
    transferService.rename(deviceName);
    _notify();
  }

  // ─── Helpers ────────────────────────────────────────────────────

  /// Actualiza el progreso y notifica solo si cambió el porcentaje entero,
  /// para no redibujar la pantalla por cada chunk.
  void _setProgress(String transferId, int progress) {
    final current = activeTransfer;
    if (current == null || current.transferId != transferId) return;
    final clamped = progress.clamp(0, 100);
    if (clamped == current.progress) return;
    activeTransfer = current.copyWith(progress: clamped);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ─── Cleanup ────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _pendingSend?.cancelToken.cancel();
    for (final r in _receives.values) {
      unawaited(r.sink.discard());
    }
    _receives.clear();
    for (final e in _incoming) {
      e.timeout?.cancel();
    }
    transferService.dispose();
    super.dispose();
  }
}

class _QueuedFile {
  final File file;
  final String fileName;
  final String peerId;
  final String peerName;
  final TransferService service;

  _QueuedFile({
    required this.file,
    required this.fileName,
    required this.peerId,
    required this.peerName,
    required this.service,
  });
}

class _IncomingRequest {
  final IncomingTransferRequest request;
  final TransferService service;
  final E2ESession session;
  final Completer<void> dismissed = Completer<void>();
  Timer? timeout;
  bool answered = false;

  _IncomingRequest(this.request, this.service, this.session);

  void dismiss() {
    if (!dismissed.isCompleted) dismissed.complete();
  }
}
