import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'splash_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../models/disk_stats.dart';
import '../models/app_config.dart';
import '../models/transfer_client.dart';
import '../models/transfer_request.dart';
import '../models/active_transfer.dart';
import '../services/files_service.dart';
import '../services/preview_service.dart';
import '../services/transfer_service.dart';
import '../services/device_name_service.dart';
import '../widgets/gradient_text.dart';
import '../widgets/disk_stats_bar.dart';
import '../widgets/search_bar.dart';
import '../widgets/file_list_item.dart';
import '../widgets/file_grid_item.dart';
import '../widgets/qr_footer.dart';
import '../widgets/upload_sheet.dart';
import '../widgets/online_clients.dart';
import '../widgets/incoming_transfer_dialog.dart';
import '../widgets/name_dialog.dart';
import '../widgets/pin_entry_dialog.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/server_mode_warning_dialog.dart';
import '../widgets/skeleton_loader.dart';
import '../services/notification_service.dart';
import '../services/received_files_service.dart';
import '../services/embedded_relay.dart';
import '../services/discovery_service.dart';
import '../services/direct_transfer_pool.dart';
import '../services/app_logger.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.serverUrl,
    this.autoServerMode = false,
  });

  /// URL del servidor. Si es null, la app entra en modo sin servidor
  /// (solo P2P + archivos recibidos).
  final String? serverUrl;

  /// Si es true, activa automáticamente el modo servidor al iniciar el relay.
  final bool autoServerMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  FilesService? _filesService;
  ApiConfig? _apiConfig;

  /// true si estamos conectados a un servidor externo.
  bool get _hasServer => widget.serverUrl != null;

  /// true si estamos en modo servidor (externo o local relay con server mode).
  bool get _isServer => _hasServer || _relay.isServerMode;

  List<FileInfo> _files = [];
  DiskStats? _stats;
  AppConfig? _config;
  bool _loading = true;
  String? _error;
  bool _isGridView = false;

  // Upload state
  List<File> _stagedFiles = [];
  bool _uploading = false;
  double _uploadProgress = 0;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _connectionLost = false;

  // ─── Notificaciones ────────────────────────────────────────────────
  final NotificationService _notificationService = NotificationService();

  // ─── P2P Transfer state ───────────────────────────────────────────
  final TransferService _transferService = TransferService();
  final DeviceNameService _deviceNameService = DeviceNameService();
  String? _myClientId;
  List<TransferClient> _onlineClients = [];
  ActiveTransfer? _activeTransfer;
  String _deviceName = '';

  // Buffer para recibir chunks
  final Map<String, _ReceiveBuffer> _receiveBuffers = {};

  // Referencia al archivo pendiente de enviar (esperando accept)
  _PendingSend? _pendingSend;

  // ─── Archivos recibidos (persistentes) ─────────────────────────────
  final ReceivedFilesService _receivedFilesService = ReceivedFilesService();
  List<FileInfo> _receivedFiles = [];

  // ─── Relay embebido (modo sin servidor) ────────────────────────────
  final EmbeddedRelay _relay = EmbeddedRelay();

  // ─── Modo Envío Directo ────────────────────────────────────────────
  final DirectTransferPool _directPool = DirectTransferPool();
  List<DiscoveredServer> _directDevices = [];
  Timer? _scanTimer;
  bool _directScanning = false;

  bool get _isDirectMode => !_hasServer && !_relay.isServerMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDirectPool();
    if (_hasServer) {
      _apiConfig = ApiConfig(widget.serverUrl!);
      _filesService = FilesService(_apiConfig!);
      _initTransfer(); // _initialLoad() se llama desde onAuthOk tras autenticar
    } else {
      // Modo sin servidor: levantar relay, luego conectarse como cliente
      _loading = false;
      _startRelay();
    }
    _loadReceivedFiles();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _directPool.disposeAll();
    _searchController.dispose();
    _transferService.dispose();
    _relay.stop();
    _notificationService.stopForeground();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Volvió a primer plano: quitar notificación de background
      _notificationService.stopForeground();
      // Reconectar WebSocket al volver a la app
      if (_apiConfig != null && !_transferService.isConnected) {
        _connectWebSocket();
      }
    } else if (state == AppLifecycleState.paused) {
      // Se fue a segundo plano: activar foreground service para mantener WS vivo
      _notificationService.startForeground();
    }
  }

  // ─── Relay embebido ────────────────────────────────────────────────

  Future<void> _startRelay() async {
    AppLogger.instance.info('[HomeScreen] starting embedded relay');
    try {
      await _relay.start();
      AppLogger.instance.info('[HomeScreen] relay started: ${_relay.url}');
      // Conectar el TransferService al relay propio
      _apiConfig = ApiConfig(_relay.url!);
      _initTransfer();
      if (widget.autoServerMode) {
        _activateServerMode();
      } else {
        // Modo envío directo — escanear la red periódicamente
        _startDirectScanning();
      }
    } catch (e) {
      AppLogger.instance.error('[HomeScreen] relay start failed', error: e);
      if (mounted) {
        setState(() => _error = 'No se pudo iniciar el relay: $e');
      }
    }
  }

  // ─── Server mode ────────────────────────────────────────────────────

  Future<void> _activateServerMode() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('server_mode_warning_dismissed') ?? false;

    if (!dismissed && mounted) {
      final confirmed = await ServerModeWarningDialog.show(context);
      if (confirmed != true) {
        // User cancelled or pressed back — go to splash
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SplashScreen()),
          );
        }
        return;
      }
      if (!mounted) return;
    }

    AppLogger.instance.info('[HomeScreen] activating server mode');
    try {
      _stopDirectScanning();
      final pin = await _relay.startServerMode();

      // Auto-autenticar con el relay local para obtener token
      final response = await http.post(
        Uri.parse('http://127.0.0.1:${_relay.port}/api/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        _transferService.setToken(token);
        AppLogger.instance.info('[HomeScreen] server mode auth OK');

        // Configurar FilesService para gestionar archivos del servidor local
        final localConfig = ApiConfig('http://127.0.0.1:${_relay.port}');
        _filesService = FilesService(localConfig);
        _filesService!.setToken(token);
      } else {
        AppLogger.instance.warn('[HomeScreen] server mode auth failed: status ${response.statusCode}');
      }

      // Reconectar WS con el nuevo token
      _connectWebSocket();

      if (mounted) {
        setState(() => _loading = true);
        await _initialLoad();
      }
    } catch (e) {
      AppLogger.instance.error('[HomeScreen] _activateServerMode error', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo activar el servidor: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // ─── Modo Envío Directo — pool + scanning ────────────────────────────

  void _initDirectPool() {
    _directPool.onSendRequest = (request) {
      _notificationService.showIncomingTransfer(request.fromName, request.fileName);
      if (mounted) _showIncomingTransferDialog(request);
    };
    _directPool.onSendAccept = (id) => _handleSendAccept(id);
    _directPool.onSendReject = (id, reason) {
      if (_pendingSend?.transferId == id) {
        _pendingSend = null;
        if (mounted) {
          setState(() => _activeTransfer = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El destinatario rechazó el envío'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    };
    _directPool.onSendCancel = (id) {
      _receiveBuffers.remove(id);
      if (_pendingSend?.transferId == id) _pendingSend = null;
      if (mounted && _activeTransfer?.transferId == id) {
        setState(() => _activeTransfer = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transferencia cancelada')),
        );
      }
    };
    _directPool.onSendComplete = (id) => _handleReceiveComplete(id);
    _directPool.onBinaryChunk = (id, data) => _handleBinaryChunk(id, data);
  }

  void _startDirectScanning() {
    _scanForDirectDevices();
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) => _scanForDirectDevices());
  }

  void _stopDirectScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (mounted) setState(() => _directDevices = []);
  }

  Future<void> _scanForDirectDevices() async {
    if (mounted) setState(() => _directScanning = true);
    final devices = await DiscoveryService().scanLan();
    if (mounted) {
      setState(() {
        _directDevices = devices;
        _directScanning = false;
      });
    }
  }

  Future<void> _onSendDirectFile(DiscoveredServer device) async {
    if (_activeTransfer != null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty || !mounted) return;
    final platformFile = result.files.first;
    if (platformFile.path == null) return;

    final file = File(platformFile.path!);
    final fileName = platformFile.name;
    final fileSize = await file.length();

    // Obtener o crear conexión al relay del destinatario
    final conn = await _directPool.getConnection(device.url, _deviceName);
    if (!mounted) return;
    if (conn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo conectar con ${device.appName}'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final transferId = _generateTransferId();
    _pendingSend = _PendingSend(
      transferId: transferId,
      file: file,
      peerId: conn.targetClientId,
      service: conn.service,
    );

    setState(() {
      _activeTransfer = ActiveTransfer(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        progress: 0,
        direction: TransferDirection.sending,
        peerName: device.appName,
        peerId: conn.targetClientId,
        waiting: true,
      );
    });

    conn.service.sendRequest(
      to: conn.targetClientId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'application/octet-stream',
      transferId: transferId,
    );

    // Reiniciar timer de inactividad al iniciar envío
    _directPool.touch(device.url);
  }

  // ─── Auto-auth para relay propio ────────────────────────────────────

  Future<void> _autoAuthWithRelay() async {
    AppLogger.instance.debug('[HomeScreen] _autoAuthWithRelay');
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:${_relay.port}/api/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': _relay.currentPin}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        _transferService.setToken(token);
        _filesService?.setToken(token);
        AppLogger.instance.info('[HomeScreen] auto-auth with relay OK');
        _connectWebSocket();
      } else {
        AppLogger.instance.warn('[HomeScreen] _autoAuthWithRelay failed: status ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.instance.error('[HomeScreen] _autoAuthWithRelay error', error: e);
    }
  }

  // ─── PIN entry para servidor externo protegido ──────────────────────

  Future<void> _showPinEntryDialog({String? errorMessage}) async {
    if (_apiConfig == null) return;
    final pin = await PinEntryDialog.show(
      context,
      error: errorMessage,
      onValidate: (pin) async {
        try {
          final response = await http.post(
            Uri.parse('${_apiConfig!.baseUrl}/api/auth'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}),
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final token = data['token'] as String;
            _transferService.setToken(token);
            _filesService?.setToken(token);
            return null; // success — dialog will close
          }
          return 'PIN incorrecto';
        } catch (e) {
          return 'Error al autenticar: $e';
        }
      },
    );
    if (!mounted) return;
    if (pin == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
      return;
    }
    // PIN was valid — reconnect and load
    _connectWebSocket();
    if (_isServer) _initialLoad();
  }

  // ─── Archivos recibidos ─────────────────────────────────────────────

  Future<void> _loadReceivedFiles() async {
    final files = await _receivedFilesService.listFiles();
    if (mounted) setState(() => _receivedFiles = files);
  }

  // ─── Data loading ──────────────────────────────────────────────────

  Future<void> _initialLoad() async {
    if (_filesService == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      AppLogger.instance.debug('[HomeScreen] _initialLoad starting');
      final results = await Future.wait([
        _filesService!.getFiles(),
        _filesService!.getStats(),
        _filesService!.getConfig(),
      ]);

      if (mounted) {
        final files = results[0] as List<FileInfo>;
        AppLogger.instance.info('[HomeScreen] initial load complete: ${files.length} files');
        setState(() {
          _files = files;
          _stats = results[1] as DiskStats;
          _config = results[2] as AppConfig;
          _loading = false;
          PreviewService.setMaxPreviewMb(_config!.previewMaxFileSizeMb);
        });
      }
    } catch (e) {
      AppLogger.instance.error('[HomeScreen] _initialLoad failed', error: e);
      if (mounted) {
        setState(() {
          _error = 'Error al conectar con el servidor';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    // Siempre refrescar archivos recibidos
    await _loadReceivedFiles();

    if (_filesService == null) return;
    try {
      final results = await Future.wait([
        _filesService!.getFiles(),
        _filesService!.getStats(),
      ]);

      if (mounted) {
        setState(() {
          _files = results[0] as List<FileInfo>;
          _stats = results[1] as DiskStats;
          _connectionLost = false;
        });
      }
    } catch (e) {
      AppLogger.instance.warn('[HomeScreen] _refreshData failed: $e');
      if (mounted && _files.isNotEmpty) {
        // Si ya tenemos datos, mostrar banner en vez de error completo
        setState(() => _connectionLost = true);
      } else if (mounted) {
        setState(() => _error = 'Error al actualizar datos');
      }
    }
  }

  // ─── P2P Transfer ─────────────────────────────────────────────────

  Future<void> _initTransfer() async {
    _deviceName = await _deviceNameService.getName();

    _transferService.onWelcome = (clientId) {
      if (mounted) setState(() => _myClientId = clientId);
    };

    _transferService.onClientsUpdate = (clients) {
      if (mounted) setState(() => _onlineClients = clients);
    };

    _transferService.onSendRequest = (request) {
      AppLogger.instance.info('[HomeScreen] incoming transfer request: ${request.fileName} from ${request.fromName}');
      // Notificación en la barra (útil si la app está en background)
      _notificationService.showIncomingTransfer(
        request.fromName,
        request.fileName,
      );
      if (mounted) _showIncomingTransferDialog(request);
    };

    _transferService.onSendAccept = (transferId) {
      _handleSendAccept(transferId);
    };

    _transferService.onSendReject = (transferId, reason) {
      if (_pendingSend?.transferId == transferId) {
        _pendingSend = null;
        if (mounted) {
          setState(() => _activeTransfer = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El destinatario rechazó el envío'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    };

    _transferService.onSendCancel = (transferId) {
      _receiveBuffers.remove(transferId);
      if (_pendingSend?.transferId == transferId) {
        _pendingSend = null;
      }
      if (mounted && _activeTransfer?.transferId == transferId) {
        setState(() => _activeTransfer = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transferencia cancelada'),
          ),
        );
      }
    };

    _transferService.onSendComplete = (transferId) {
      _handleReceiveComplete(transferId);
    };

    _transferService.onBinaryChunk = (transferId, data) {
      _handleBinaryChunk(transferId, data);
    };

    _transferService.onDisconnected = () {
      AppLogger.instance.warn('[HomeScreen] WS disconnected, will reconnect in 3s');
      if (mounted) {
        setState(() {
          _myClientId = null;
          _onlineClients = [];
          _activeTransfer = null;
        });
        // Reintentar conexión después de 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _connectWebSocket();
        });
      }
    };

    _transferService.onFilesChanged = () {
      if (mounted) _refreshData();
    };

    _transferService.onAuthRequired = () {
      if (!mounted) return;
      // Si somos el servidor local, auto-autenticar con nuestro propio PIN
      if (!_hasServer && _relay.isServerMode && _relay.currentPin != null) {
        _autoAuthWithRelay();
      } else {
        _showPinEntryDialog();
      }
    };

    _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    if (_apiConfig == null) return;
    // Si hay token, el servidor requiere auth_ok antes de aceptar hello.
    // Registramos via onAuthOk para respetar el handshake (PIN antes de nombre).
    // Sin token (relay sin PIN), registramos directamente.
    _transferService.onAuthOk = () async {
      await _ensureDeviceName();
      _transferService.register(_deviceName);
      _transferService.setReceiving(true);
      if (_hasServer) _initialLoad();
    };
    _transferService.connect(_apiConfig!);
    if (!_transferService.hasToken) {
      if (!_hasServer && !widget.autoServerMode) {
        // Relay propio sin PIN, sin activar servidor — pedir nombre ahora.
        // Si autoServerMode, el nombre se pide en onAuthOk (después del diálogo de servidor).
        await _ensureDeviceName();
      }
      // Para servidor externo sin token: enviar hello de todas formas;
      // el servidor cerrará con 4401 → onAuthRequired → PIN dialog.
      // Después de autenticar, onAuthOk pedirá el nombre y registrará.
      _transferService.register(_deviceName);
      _transferService.setReceiving(true);
    }
  }

  /// Asegura que el nombre del dispositivo esté configurado.
  /// Si es la primera vez, asigna uno aleatorio automáticamente (sin modal).
  Future<void> _ensureDeviceName() async {
    _deviceName = await _deviceNameService.getName();
    final isFirst = await _deviceNameService.isFirstLaunch();
    if (isFirst) {
      final name = _deviceNameService.generateRandomName();
      await _deviceNameService.saveName(name);
      _deviceName = name;
    }
    _relay.setDeviceName(_deviceName);
  }

  // ─── Enviar archivo P2P ───────────────────────────────────────────

  Future<void> _onSendFile(String clientId, String peerName) async {
    if (_activeTransfer != null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;

    final platformFile = result.files.first;
    if (platformFile.path == null) return;

    final file = File(platformFile.path!);
    final fileName = platformFile.name;
    final fileSize = await file.length();
    final transferId = _generateTransferId();

    _pendingSend = _PendingSend(
      transferId: transferId,
      file: file,
      peerId: clientId,
      service: _transferService,
    );

    setState(() {
      _activeTransfer = ActiveTransfer(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        progress: 0,
        direction: TransferDirection.sending,
        peerName: peerName,
        peerId: clientId,
        waiting: true,
      );
    });

    _transferService.sendRequest(
      to: clientId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'application/octet-stream',
      transferId: transferId,
    );
  }

  Future<void> _handleSendAccept(String transferId) async {
    final pending = _pendingSend;
    if (pending == null || pending.transferId != transferId) return;

    // Marcar como activo (ya no waiting)
    if (mounted) {
      setState(() {
        _activeTransfer = _activeTransfer?.copyWith(waiting: false);
      });
    }

    // Leer bytes del archivo y enviar
    final fileBytes = await pending.file.readAsBytes();

    await pending.service.sendFile(
      transferId: pending.transferId,
      fileBytes: fileBytes,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _activeTransfer = _activeTransfer?.copyWith(
              progress: (progress * 100).round(),
            );
          });
        }
      },
    );

    _pendingSend = null;
    if (mounted) {
      setState(() => _activeTransfer = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo enviado correctamente')),
      );
    }
  }

  // ─── Recibir archivo P2P ──────────────────────────────────────────

  Future<void> _showIncomingTransferDialog(
    IncomingTransferRequest request,
  ) async {
    final accepted = await IncomingTransferDialog.show(context, request);

    if (accepted == true) {
      _acceptTransfer(request);
    } else {
      _transferService.reject(request.transferId);
    }
  }

  void _acceptTransfer(IncomingTransferRequest request) {
    _receiveBuffers[request.transferId] = _ReceiveBuffer(
      chunks: [],
      received: 0,
      total: request.fileSize,
      fileName: request.fileName,
      mimeType: request.mimeType,
    );

    setState(() {
      _activeTransfer = ActiveTransfer(
        transferId: request.transferId,
        fileName: request.fileName,
        fileSize: request.fileSize,
        progress: 0,
        direction: TransferDirection.receiving,
        peerName: request.fromName,
        peerId: request.from,
        waiting: false,
      );
    });

    _transferService.accept(request.transferId);
  }

  void _handleBinaryChunk(String transferId, Uint8List data) {
    final buffer = _receiveBuffers[transferId];
    if (buffer == null) return;

    buffer.chunks.add(data);
    buffer.received += data.length;

    final progress = (buffer.received / buffer.total * 100).round();

    if (mounted) {
      setState(() {
        _activeTransfer = _activeTransfer?.copyWith(progress: progress);
      });
    }
  }

  Future<void> _handleReceiveComplete(String transferId) async {
    final buffer = _receiveBuffers.remove(transferId);
    if (buffer == null) return;

    // Ensamblar chunks y guardar archivo
    final totalLength = buffer.chunks.fold<int>(0, (sum, c) => sum + c.length);
    final assembled = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in buffer.chunks) {
      assembled.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    // Guardar en directorio de archivos recibidos
    final filePath = await _receivedFilesService.saveFile(
      buffer.fileName,
      assembled,
    );
    final peerName = _activeTransfer?.peerName ?? 'otro dispositivo';
    _notificationService.showTransferComplete(buffer.fileName, peerName);

    if (mounted) {
      setState(() => _activeTransfer = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('"${buffer.fileName}" recibido'),
          action: SnackBarAction(
            label: 'Abrir',
            textColor: AppColors.accentPrimary,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
      // Refrescar archivos recibidos
      await _loadReceivedFiles();
      // Refrescar archivos del servidor si hay servidor
      if (_isServer) await _refreshData();
    }
  }

  // ─── Cancelar transferencia ───────────────────────────────────────

  void _cancelTransfer() {
    final transfer = _activeTransfer;
    if (transfer == null) return;

    // Para envíos salientes usar el servicio que inició la transferencia
    final serviceToCancel = _pendingSend?.service ?? _transferService;
    serviceToCancel.cancel(transfer.transferId);
    _receiveBuffers.remove(transfer.transferId);
    _pendingSend = null;

    setState(() => _activeTransfer = null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transferencia cancelada')),
    );
  }

  // ─── Utilidades ───────────────────────────────────────────────────

  Future<void> _renameDevice() async {
    final newName = await NameDialog.show(context, _deviceName);
    if (newName == null || !mounted) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await _deviceNameService.saveName(trimmed);
    setState(() => _deviceName = trimmed);
    _transferService.rename(trimmed);
  }

  String _generateTransferId() {
    // Genera un UUID v4 simple (mismo formato que crypto.randomUUID del web)
    final now = DateTime.now().microsecondsSinceEpoch;
    final hex = now.toRadixString(16).padLeft(12, '0');
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4000-8000-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0')}';
  }

  // ─── Upload ────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (files.isEmpty) return;

    setState(() {
      _stagedFiles = [..._stagedFiles, ...files];
    });

    _showUploadSheet();
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return UploadSheet(
            files: _stagedFiles,
            uploading: _uploading,
            uploadProgress: _uploadProgress,
            maxFileSizeMb: _config?.maxFileSizeMb,
            onRemove: (index) {
              setState(() {
                _stagedFiles = List.from(_stagedFiles)..removeAt(index);
              });
              setSheetState(() {});
              if (_stagedFiles.isEmpty) Navigator.of(ctx).pop();
            },
            onClearAll: () {
              setState(() => _stagedFiles = []);
              Navigator.of(ctx).pop();
            },
            onUpload: () async {
              setState(() {
                _uploading = true;
                _uploadProgress = 0;
              });
              setSheetState(() {});

              try {
                await _filesService!.uploadFiles(_stagedFiles);

                setState(() {
                  _uploading = false;
                  _uploadProgress = 0;
                  _stagedFiles = [];
                });
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _refreshData();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Archivos subidos correctamente'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _uploading = false;
                    _uploadProgress = 0;
                  });
                  setSheetState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al subir: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
          );
        },
      ),
    );
  }

  // ─── Download ──────────────────────────────────────────────────────

  Future<void> _onDownload(FileInfo file) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Descargando "${file.name}"...')),
    );

    try {
      final url = _filesService!.getDownloadUrl(file.name);
      final response = await http.get(
        Uri.parse(url),
        headers: _filesService!.authHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Status ${response.statusCode}');
      }

      final dir = await _getDownloadDir();
      final filePath = '${dir.path}/${file.name}';
      await File(filePath).writeAsBytes(response.bodyBytes);
      _notificationService.showDownloadComplete(file.name);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text('"${file.name}" descargado'),
            action: SnackBarAction(
              label: 'Abrir',
              textColor: AppColors.accentPrimary,
              onPressed: () => OpenFilex.open(filePath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar "${file.name}"'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<Directory> _getDownloadDir() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      // Use public Downloads folder on Android so gallery/file managers can see files
      baseDir = Directory('/storage/emulated/0/Download');
      if (!await baseDir.exists()) {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final srvDir = Directory('${baseDir.path}/SrvFiles');
    if (!await srvDir.exists()) {
      await srvDir.create(recursive: true);
    }
    return srvDir;
  }

  // ─── Share ─────────────────────────────────────────────────────────

  Future<void> _onShare(FileInfo file) async {
    try {
      final url = _filesService!.getDownloadUrl(file.name);
      final response = await http.get(
        Uri.parse(url),
        headers: _filesService!.authHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Status ${response.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${file.name}';
      await File(tempPath).writeAsBytes(response.bodyBytes);

      await Share.shareXFiles([XFile(tempPath)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al compartir "${file.name}"'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // ─── Filtrado ──────────────────────────────────────────────────────

  List<FileInfo> get _filteredFiles {
    if (_searchQuery.isEmpty) return _files;
    final query = _searchQuery.toLowerCase();
    return _files.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  // ─── Conectar a servidor desde HomeScreen ────────────────────────

  void _showConnectDialog() => _showConnectSheet();

  void _showConnectSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConnectSheet(
        currentServerUrl: widget.serverUrl,
        webUrl: (_config != null && widget.serverUrl != null && _config!.frontendPort != _config!.port)
            ? 'http://${_config!.lanIp}:${_config!.frontendPort}'
            : null,
        relayIp: _relay.localIp,
        relayPort: _relay.port,
        relayPin: _relay.isServerMode ? _relay.currentPin : null,
        isRelayServer: _relay.isServerMode,
        isRelayRunning: _relay.isRunning,
        onConnect: (url) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(serverUrl: url)),
          );
        },
        onDisconnect: () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SplashScreen()),
          );
        },
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredFiles;
    final hasOnlinePeers = _onlineClients
        .where((c) => c.clientId != _myClientId)
        .isNotEmpty;

    return Scaffold(
      // ─── AppBar ──────────────────────────────────────────────────
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Row(
          children: [
            Hero(
              tag: 'srvfiles-logo',
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderMedium),
                ),
                child: const Center(
                  child: Icon(
                    Icons.folder_shared_rounded,
                    color: AppColors.accentPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GradientText(
              _config?.appName ?? 'SrvFiles',
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
        actions: [
          // Indicador de peers online con pulse
          if (hasOnlinePeers)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: PulsingDot(size: 8),
            ),
          // Chip de nombre del dispositivo — tappable para renombrar
          _buildDeviceNameChip(),
          // Label de servidor tappable
          _buildServerLabel(),
          const SizedBox(width: AppSpacing.sm),
        ],
        // Disk stats ocupa el 100% del ancho debajo del título y la IP
        bottom: _isServer && _stats != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: DiskStatsBar(stats: _stats, fullWidth: true),
              )
            : null,
      ),

      // ─── Body ────────────────────────────────────────────────────
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    // Banner de pérdida de conexión parcial
                    if (_connectionLost && _isServer)
                      _buildConnectionBanner(),
                    Expanded(child: RefreshIndicator(
                  onRefresh: _refreshData,
                  color: AppColors.accentPrimary,
                  child: CustomScrollView(
                    slivers: [
                      // Online clients (P2P) — visible en ambos modos
                      SliverToBoxAdapter(
                        child: OnlineClients(
                          clients: _onlineClients,
                          myClientId: _myClientId,
                          activeTransfer: _activeTransfer,
                          onSendFile: _onSendFile,
                          onCancelTransfer: _cancelTransfer,
                          onViewServer: (url) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => HomeScreen(serverUrl: url),
                              ),
                            );
                          },
                        ),
                      ),

                      // ─── Modo Envío Directo: dispositivos en la red ─
                      if (_isDirectMode)
                        SliverToBoxAdapter(child: _buildDirectDevicesSection()),

                      // ─── Modo servidor: archivos del server ─────
                      // Se ocultan cuando se pierde la conexión
                      if (_isServer && !_connectionLost) ...[
                        SliverToBoxAdapter(child: _buildToolbar(theme, filtered)),
                        if (filtered.isEmpty)
                          SliverToBoxAdapter(child: _buildEmptyServerFiles(theme))
                        else if (_isGridView)
                          _buildGrid(filtered)
                        else
                          _buildList(filtered),
                      ],

                      // ─── Tabla de archivos recibidos (ambos modos) ──
                      SliverToBoxAdapter(child: _buildReceivedFilesSection(theme)),

                      // QR solo en modo servidor (y conectado)
                      if (_isServer && !_connectionLost)
                        SliverToBoxAdapter(child: QrFooter(config: _config)),

                      // Espacio inferior para no tapar con FAB
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
                )),
                  ],
                ),

      // ─── FAB upload — solo en modo servidor ──────────────────────
      floatingActionButton: _isServer && !_loading && _error == null && !_connectionLost
          ? FloatingActionButton(
              onPressed: _uploading
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _pickFiles();
                    },
              child: _uploading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded),
            )
          : null,
    );
  }

  // ─── Sub-builds ────────────────────────────────────────────────────

  // ─── Modo Envío Directo — UI ──────────────────────────────────────

  Widget _buildDirectDevicesSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.borderMd,
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.wifi_find_rounded, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Dispositivos en la red',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_directScanning)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.textMuted,
                      ),
                    )
                  else
                    InkWell(
                      onTap: _scanForDirectDevices,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.refresh_rounded, size: 14, color: AppColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
            if (_directDevices.isEmpty && !_directScanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                child: Text(
                  'No se encontraron dispositivos en la red',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              )
            else
              ..._directDevices.map((d) => _buildDirectDeviceRow(d)),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectDeviceRow(DiscoveredServer device) {
    final isActive = _activeTransfer != null && _activeTransfer!.peerName == device.appName;
    final isOtherActive = _activeTransfer != null && !isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const PulsingDot(size: 8),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_android, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        device.appName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  device.ip,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isActive && _activeTransfer != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.textMuted,
              onPressed: _cancelTransfer,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            )
          else
            TextButton.icon(
              onPressed: isOtherActive ? null : () => _onSendDirectFile(device),
              icon: const Icon(Icons.upload_rounded, size: 14),
              label: const Text('Enviar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.dangerBg,
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.danger, size: 18),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Conexión perdida con el servidor',
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _refreshData();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const SkeletonLoader();
  }

  Widget _buildDeviceNameChip() {
    if (_deviceName.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _renameDevice,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              size: 13,
              color: AppColors.textMuted.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              _deviceName,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerLabel() {
    // Siempre icono wifi — la info completa va en el sheet.
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _showConnectDialog,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Icon(
          (_hasServer || _relay.isRunning)
              ? Icons.wifi_rounded
              : Icons.link_rounded,
          size: 18,
          color: (_hasServer || _relay.isRunning)
              ? AppColors.accentPrimary
              : AppColors.textMuted.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: _initialLoad,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, List<FileInfo> filtered) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FileSearchBar(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  onClear: () => setState(() => _searchQuery = ''),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _viewToggleButton(
                icon: Icons.view_list_rounded,
                active: !_isGridView,
                onPressed: () => setState(() => _isGridView = false),
              ),
              _viewToggleButton(
                icon: Icons.grid_view_rounded,
                active: _isGridView,
                onPressed: () => setState(() => _isGridView = true),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} archivo${filtered.length != 1 ? 's' : ''}'
                '${_searchQuery.isNotEmpty ? ' (filtrando de ${_files.length})' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewToggleButton({
    required IconData icon,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: active ? AppColors.accentPrimary : AppColors.textMuted,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEmptyServerFiles(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.md,
      ),
      child: Center(
        child: Column(
          children: [
            Text(
              _searchQuery.isNotEmpty ? '🔍' : '📂',
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No se encontraron archivos que coincidan con "$_searchQuery"'
                  : 'No hay archivos aún',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedFilesSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Separador visual si hay archivos del servidor arriba
          if (_isServer && _files.isNotEmpty)
            const Divider(color: AppColors.borderSubtle, height: 1),
          if (_isServer && _files.isNotEmpty)
            const SizedBox(height: AppSpacing.md),

          // Header de sección
          Row(
            children: [
              const Icon(
                Icons.download_done_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Archivos recibidos',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_receivedFiles.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '(${_receivedFiles.length})',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          if (_receivedFiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text(
                  'Aún no recibiste archivos',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ...List.generate(_receivedFiles.length, (index) {
              final file = _receivedFiles[index];
              return FileListItem(
                file: file,
                onDownload: () => OpenFilex.open(file.downloadUrl),
                onPreview: () => unawaited(PreviewService.previewLocalFile(
                  filePath: file.downloadUrl,
                  fileName: file.name,
                  context: context,
                )),
                onShare: () async {
                  await Share.shareXFiles([XFile(file.downloadUrl)]);
                },
                onDelete: () => _deleteReceivedFile(file),
                downloadIcon: Icons.remove_red_eye_rounded,
                downloadTooltip: 'Abrir',
              );
            }),
        ],
      ),
    );
  }

  Future<void> _deleteReceivedFile(FileInfo file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('¿Eliminar "${file.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _receivedFilesService.deleteFile(file.name);
      await _loadReceivedFiles();
    }
  }

  Future<void> _deleteServerFile(FileInfo file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('¿Eliminar "${file.name}" del servidor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && _filesService != null) {
      final success = await _filesService!.deleteFile(file.name);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${file.name}" eliminado')),
        );
        await _refreshData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar "${file.name}"'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  SliverList _buildList(List<FileInfo> files) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final file = files[index];
          return FileListItem(
            file: file,
            onDownload: () => _onDownload(file),
            onPreview: () => unawaited(PreviewService.previewServerFile(
              file: file,
              config: _apiConfig!,
              sessionToken: _filesService?.sessionToken,
              context: context,
            )),
            onDelete: () => _deleteServerFile(file),
          );
        },
        childCount: files.length,
      ),
    );
  }

  SliverPadding _buildGrid(List<FileInfo> files) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          // Responsive: 2 columnas en portrait, más en landscape/tablet
          final crossAxisCount = width > 600 ? 4 : (width > 400 ? 3 : 2);

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final file = files[index];
                return FileGridItem(
                  file: file,
                  onDownload: () => _onDownload(file),
                  onShare: () => _onShare(file),
                  onPreview: () => unawaited(PreviewService.previewServerFile(
                    file: file,
                    config: _apiConfig!,
                    sessionToken: _filesService?.sessionToken,
                    context: context,
                  )),
                  onDelete: () => _deleteServerFile(file),
                );
              },
              childCount: files.length,
            ),
          );
        },
      ),
    );
  }
}

// ─── Clases auxiliares internas ───────────────────────────────────────

class _ReceiveBuffer {
  final List<Uint8List> chunks;
  int received;
  final int total;
  final String fileName;
  final String mimeType;

  _ReceiveBuffer({
    required this.chunks,
    required this.received,
    required this.total,
    required this.fileName,
    required this.mimeType,
  });
}

class _PendingSend {
  final String transferId;
  final File file;
  final String peerId;
  /// Servicio a través del cual enviar los chunks (main o pool).
  final TransferService service;

  const _PendingSend({
    required this.transferId,
    required this.file,
    required this.peerId,
    required this.service,
  });
}

// ─── Bottom sheet de conexión a servidor ──────────────────────────────

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({
    required this.onConnect,
    required this.onDisconnect,
    this.currentServerUrl,
    this.webUrl,
    this.relayIp,
    this.relayPort = 3001,
    this.relayPin,
    this.isRelayServer = false,
    this.isRelayRunning = false,
  });

  final void Function(String url) onConnect;
  final VoidCallback onDisconnect;
  final String? currentServerUrl;
  final String? webUrl;             // URL del frontend web (distinta al backend)
  final String? relayIp;
  final int relayPort;
  final String? relayPin;
  final bool isRelayServer;
  final bool isRelayRunning;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final _discovery = DiscoveryService();
  final _ipController = TextEditingController();

  bool _scanning = true;
  List<DiscoveredServer> _servers = [];

  @override
  void initState() {
    super.initState();
    // Solo escanear si no somos el servidor (o si estamos conectados a uno externo)
    if (widget.currentServerUrl != null || !widget.isRelayServer) {
      _scan();
    } else {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _servers = [];
    });
    final results = await _discovery.scanLan();
    if (mounted) {
      setState(() {
        _servers = results;
        _scanning = false;
      });
    }
  }

  void _connectTo(String url) {
    Navigator.of(context).pop();
    widget.onConnect(url);
  }

  void _connectManual() {
    final input = _ipController.text.trim();
    if (input.isEmpty) return;
    String url = input;
    if (!url.startsWith('http')) url = 'http://$url';
    if (!RegExp(r':\d+$').hasMatch(url)) url = '$url:3001';
    _connectTo(url);
  }

  /// Fila de URL copiable con label e icono.
  Widget _buildUrlRow(String label, IconData icon, String address) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted.withValues(alpha: 0.6), size: 14),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copiado: $address'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.accentPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.copy_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.7), size: 14),
          ),
        ),
      ],
    );
  }

  /// Card unificada para mostrar info de un servidor (local o externo).
  Widget _buildServerInfoCard({
    required String address,
    required String badgeText,
    required IconData icon,
    String? webAddress,
    String? pin,
    String? description,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.accentPrimary.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge
            Row(
              children: [
                Icon(icon, color: AppColors.accentPrimary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: AppColors.accentPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // URLs con botón copiar
            _buildUrlRow('Servidor', Icons.dns_rounded, address),
            if (webAddress != null && webAddress != address) ...[
              const SizedBox(height: 6),
              _buildUrlRow('Web', Icons.language_rounded, webAddress),
            ],
            if (pin != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.lock_rounded,
                      color: AppColors.textMuted.withValues(alpha: 0.6),
                      size: 14),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 52,
                    child: Text(
                      'PIN',
                      style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pin,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (description != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocalServer = widget.isRelayServer && widget.currentServerUrl == null;
    final otherServers = _servers
        .where((s) => s.url != widget.currentServerUrl)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
            ),
            child: Text(
              isLocalServer
                  ? 'Tu servidor'
                  : widget.currentServerUrl != null
                      ? 'Servidor conectado'
                      : 'Conectar a servidor',
              style: theme.textTheme.titleMedium,
            ),
          ),

          // ─── Card de servidor (local o externo) ──────────────────
          if (isLocalServer)
            _buildServerInfoCard(
              address: '${widget.relayIp ?? '...'}:${widget.relayPort}',
              badgeText: 'Activo',
              icon: Icons.wifi_tethering_rounded,
              pin: widget.relayPin,
              description: 'Otros dispositivos pueden conectarse desde el navegador a esta dirección.',
            )
          else if (widget.currentServerUrl != null) ...[
            _buildServerInfoCard(
              address: widget.currentServerUrl!
                  .replaceAll('http://', '')
                  .replaceAll('https://', ''),
              webAddress: widget.webUrl
                  ?.replaceAll('http://', '')
                  .replaceAll('https://', ''),
              badgeText: 'Conectado',
              icon: Icons.wifi_rounded,
              description: 'Servidor al que estás conectado actualmente.',
            ),
            const Divider(
              color: AppColors.borderSubtle,
              indent: AppSpacing.lg,
              endIndent: AppSpacing.lg,
              height: 1,
            ),
          ],

          // ─── Escaneo / conectar (solo si NO soy servidor local) ─
          if (!isLocalServer) ...[
            // Spinner o lista de servidores encontrados
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.accentPrimary,
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text(
                        'Buscando servidores...',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else if (otherServers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm,
                ),
                child: Text(
                  'No se encontraron otros servidores en la red.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else ...[
              ...otherServers.map(
                (server) => ListTile(
                  onTap: () => _connectTo(server.url),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.computer_rounded,
                      color: AppColors.accentPrimary,
                      size: 18,
                    ),
                  ),
                  title: Text(server.appName, style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    server.ip,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
              const Divider(
                color: AppColors.borderSubtle,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
            ],

            // Campo manual
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _connectManual(),
                      decoration: const InputDecoration(
                        hintText: '192.168.1.x:3001',
                        prefixIcon: Icon(Icons.lan_rounded, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _connectManual,
                    child: const Text('Conectar'),
                  ),
                ],
              ),
            ),

            // Botón para re-escanear
            if (!_scanning)
              Center(
                child: TextButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Volver a escanear', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                ),
              ),
          ],

          // Desconectarse → volver a splash
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDisconnect();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              child: const Text('Desconectarse', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
