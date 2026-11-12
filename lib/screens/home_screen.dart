import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'splash_screen.dart';
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../services/app_logger.dart';
import '../services/auth_service.dart';
import '../services/files_service.dart';
import '../services/preview_service.dart';
import '../services/server_history.dart';
import '../services/transfer_service.dart';
import '../services/device_name_service.dart';
import '../services/notification_service.dart';
import '../services/received_files_service.dart';
import '../services/direct_transfer_pool.dart';
import '../services/discovery_service.dart';
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
import '../features/files/files_controller.dart';
import '../features/transfer/transfer_controller.dart';
import '../features/server/server_controller.dart';
import '../features/server/connect_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.serverUrl,
    this.autoServerMode = false,
  });

  final String? serverUrl;
  final bool autoServerMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ─── Controllers ──────────────────────────────────────────────────
  late final FilesController _filesCtrl;
  late final TransferController _transferCtrl;
  late final ServerController _serverCtrl;
  final NotificationService _notificationService = NotificationService();
  final ReceivedFilesService _receivedFilesService = ReceivedFilesService();
  final AuthService _authService = const AuthService();

  ApiConfig? _apiConfig;
  final _searchController = TextEditingController();

  bool _pinDialogOpen = false;
  bool _inBackground = false;

  bool get _hasServer => widget.serverUrl != null;
  bool get _isServer => _hasServer || _serverCtrl.relay.isServerMode;
  bool get _isDirectMode => !_hasServer && !_serverCtrl.relay.isServerMode;

  /// Recibidos (separados de los archivos del servidor).
  final ValueNotifier<List<FileInfo>> _receivedFiles = ValueNotifier([]);

  // ─── Lifecycle ────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _serverCtrl = ServerController(directPool: DirectTransferPool());

    _filesCtrl = FilesController()..onAuthRequired = _handleAuthRequired;

    _transferCtrl = TransferController(
      transferService: TransferService(),
      deviceNameService: DeviceNameService(),
      notificationService: _notificationService,
      receivedFilesService: _receivedFilesService,
      showSnackBar: _showSnackBar,
      showIncomingDialog: (req, sas, dismissed) async {
        if (!mounted) return null;
        return IncomingTransferDialog.show(context, req, sas: sas, dismissed: dismissed);
      },
      onAuthRequired: _handleAuthRequired,
      onFilesChanged: _onFilesChanged,
      openFile: (path) => OpenFilex.open(path),
    );
    _transferCtrl.addListener(_updateForegroundService);

    // Las transferencias que llegan por conexiones del pool de envío directo
    // las maneja el mismo controller, respondiendo por esa conexión.
    _serverCtrl.directPool
      ..onConnectionOpened = _transferCtrl.attachService
      ..isBusy = _transferCtrl.isServiceBusy
      ..onConnectionClosed = _transferCtrl.handleConnectionClosed;

    _notificationService.onTap = (path) => OpenFilex.open(path);

    if (_hasServer) {
      _apiConfig = ApiConfig(widget.serverUrl!);
      _filesCtrl.setService(FilesService(_apiConfig!), _apiConfig!);
      unawaited(_serverCtrl.relay.stop()); // no se usa contra un servidor remoto
      unawaited(_initRemote());
    } else {
      _filesCtrl.loading = false;
      unawaited(_initLocal());
    }
    unawaited(_loadReceivedFiles());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transferCtrl.removeListener(_updateForegroundService);
    _searchController.dispose();
    _transferCtrl.dispose();
    _serverCtrl.dispose();
    _filesCtrl.dispose();
    _receivedFiles.dispose();
    _notificationService.onTap = null;
    unawaited(_notificationService.stopForeground());
    unawaited(PreviewService.clearCache());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      unawaited(_notificationService.stopForeground());
      _serverCtrl.resumeScanning();
      _transferCtrl.transferService.reconnectNow();
    } else if (state == AppLifecycleState.paused) {
      _inBackground = true;
      _serverCtrl.pauseScanning();
      _updateForegroundService();
    }
  }

  /// El servicio en primer plano solo hace falta en segundo plano y si hay
  /// algo que mantener vivo: modo servidor o una transferencia en curso.
  void _updateForegroundService() {
    if (!_inBackground) return;
    final needed = _serverCtrl.relay.isServerMode || _transferCtrl.activeTransfer != null;
    if (needed) {
      unawaited(_notificationService.startForeground());
    } else {
      unawaited(_notificationService.stopForeground());
    }
  }

  // ─── Initialisation helpers ───────────────────────────────────────

  /// Cliente de un servidor remoto: usa el token guardado si hay uno; si no,
  /// el servidor cierra el WS con 4401 y se pide el PIN.
  Future<void> _initRemote() async {
    await _transferCtrl.initTransfer();
    final token = await _authService.getSavedToken(widget.serverUrl!);
    if (token != null) {
      _transferCtrl.transferService.setToken(token);
      _filesCtrl.filesService?.setToken(token);
    }
    if (!mounted) return;
    unawaited(_filesCtrl.initialLoad());
    await _connectWebSocket();
  }

  /// Modo directo o servidor local: arranca (o reutiliza) el relay embebido.
  Future<void> _initLocal() async {
    final url = await _serverCtrl.startRelay();
    if (!mounted) return;
    if (url == null) {
      _showSnackBar('No se pudo iniciar el relay local. ¿Estás conectado a una red wifi?', isError: true);
      return;
    }
    await _transferCtrl.initTransfer();
    if (!mounted) return;
    _serverCtrl.relay.setDeviceName(_transferCtrl.deviceName);
    // La app se conecta a su propio relay por loopback: así queda marcada
    // como dueña (isOwner) y los demás pueden enviarle archivos.
    _apiConfig = ApiConfig(_serverCtrl.relay.loopbackUrl);

    if (widget.autoServerMode) {
      // Activar antes de conectar: así el WS ya se abre con token.
      final ok = await _activateServerMode();
      if (!ok || !mounted) return;
      await _connectWebSocket();
      await _filesCtrl.initialLoad();
    } else {
      await _connectWebSocket();
      _serverCtrl.startDirectScanning();
    }
  }

  /// Devuelve true si el modo servidor quedó activo.
  Future<bool> _activateServerMode() async {
    try {
      final pin = await _serverCtrl.activateServerMode(
        checkWarning: () async {
          if (!mounted) return false;
          final result = await ServerModeWarningDialog.show(context);
          return result == true;
        },
        transferService: _transferCtrl.transferService,
        setFilesService: (svc, cfg) => _filesCtrl.setService(svc, cfg),
      );
      if (pin == null) {
        if (mounted) _goToSplash();
        return false;
      }
      return true;
    } catch (e) {
      AppLogger.instance.error('[Home] activateServerMode failed', error: e);
      _showSnackBar('No se pudo activar el modo servidor', isError: true);
      if (mounted) _goToSplash();
      return false;
    }
  }

  Future<void> _connectWebSocket() async {
    final config = _apiConfig;
    if (config == null) return;
    await _transferCtrl.connectWebSocket(
      config,
      onAuthOk: () {
        _serverCtrl.relay.setDeviceName(_transferCtrl.deviceName);
      },
    );
  }

  void _handleAuthRequired() {
    if (!mounted) return;
    if (!_hasServer && _serverCtrl.relay.isServerMode) {
      // El propio relay: renovar el token sin pedir PIN.
      if (_serverCtrl.autoAuthWithRelay(_transferCtrl.transferService, _filesCtrl.filesService)) {
        unawaited(_connectWebSocket());
        unawaited(_filesCtrl.refreshData());
      }
      return;
    }
    if (_hasServer) unawaited(_authService.clearToken(widget.serverUrl!));
    unawaited(_showPinEntryDialog());
  }

  Future<void> _showPinEntryDialog() async {
    final config = _apiConfig;
    if (config == null || _pinDialogOpen || !mounted) return;
    _pinDialogOpen = true;
    String? pin;
    try {
      pin = await PinEntryDialog.show(
        context,
        onValidate: (pin) async {
          final result = await _authService.login(config.baseUrl, pin);
          switch (result) {
            case AuthSuccess(:final token):
              _transferCtrl.transferService.setToken(token);
              _filesCtrl.filesService?.setToken(token);
              return null;
            case AuthFailure(:final message):
              return message;
          }
        },
      );
    } finally {
      _pinDialogOpen = false;
    }
    if (!mounted) return;
    if (pin == null) {
      _goToSplash();
      return;
    }
    unawaited(_connectWebSocket());
    unawaited(_filesCtrl.initialLoad());
  }

  void _goToSplash() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  void _openServer(String url) {
    unawaited(const ServerHistory().saveLastServer(url));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(serverUrl: url)),
    );
  }

  // ─── Data helpers ─────────────────────────────────────────────────

  Future<void> _loadReceivedFiles() async {
    try {
      final files = await _receivedFilesService.listFiles();
      if (mounted) _receivedFiles.value = files;
    } catch (e) {
      AppLogger.instance.warn('[Home] could not list received files: $e');
    }
  }

  Future<void> _onFilesChanged() async {
    await _loadReceivedFiles();
    await _filesCtrl.refreshData();
  }

  Future<void> _refreshData() => _onFilesChanged();

  // ─── Upload ───────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    final picked = await _filesCtrl.pickFiles();
    if (picked.isNotEmpty && mounted) _showUploadSheet();
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: _filesCtrl,
        builder: (ctx, _) => PopScope(
          // No cerrar la hoja a mitad de subida.
          canPop: !_filesCtrl.uploading,
          child: UploadSheet(
            files: _filesCtrl.stagedFiles,
            uploading: _filesCtrl.uploading,
            uploadProgress: _filesCtrl.uploadProgress,
            maxFileSizeMb: _filesCtrl.config?.maxFileSizeMb,
            onCancel: _filesCtrl.cancelUpload,
            onRemove: (index) {
              _filesCtrl.removeStagedFile(index);
              if (_filesCtrl.stagedFiles.isEmpty) Navigator.of(ctx).pop();
            },
            onClearAll: () {
              _filesCtrl.clearStagedFiles();
              Navigator.of(ctx).pop();
            },
            onUpload: () => _upload(ctx),
          ),
        ),
      ),
    );
  }

  Future<void> _upload(BuildContext sheetContext) async {
    try {
      final failed = await _filesCtrl.uploadStagedFiles();
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      if (failed.isEmpty) {
        _showSnackBar('Archivos subidos correctamente');
      } else {
        _showSnackBar('No se pudieron subir: ${failed.join(', ')}', isError: true);
      }
    } on OperationCancelledException {
      _showSnackBar('Subida cancelada');
    } on AuthRequiredException {
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    } on ServerException catch (e) {
      _showSnackBar(e.message, isError: true);
    } catch (e) {
      AppLogger.instance.error('[Home] upload failed', error: e);
      _showSnackBar('No se pudieron subir los archivos. Revisá la conexión.', isError: true);
    }
  }

  // ─── Download / Share ─────────────────────────────────────────────

  Future<void> _onDownload(FileInfo file) async {
    if (_filesCtrl.isDownloading(file.name)) return;
    String? filePath;
    try {
      filePath = await _filesCtrl.download(file);
    } on OperationCancelledException {
      _showSnackBar('Descarga cancelada');
      return;
    }
    if (!mounted) return;
    if (filePath != null) {
      unawaited(_notificationService.showDownloadComplete(file.name, path: filePath));
      _showSnackBar(
        '"${file.name}" descargado',
        actionLabel: 'Abrir',
        onAction: () => OpenFilex.open(filePath!),
      );
    } else {
      _showSnackBar('No se pudo descargar "${file.name}"', isError: true);
    }
  }

  Future<void> _onShare(FileInfo file) async {
    final tempPath = await _filesCtrl.prepareShare(file);
    if (tempPath != null) {
      await SharePlus.instance.share(ShareParams(files: [XFile(tempPath)]));
    } else if (mounted) {
      _showSnackBar('No se pudo compartir "${file.name}"', isError: true);
    }
  }

  Future<void> _shareLogs() async {
    final file = AppLogger.instance.logFile;
    if (file == null || !await file.exists()) {
      _showSnackBar('Todavía no hay registros de errores');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Registros de SrvFiles'));
  }

  // ─── Send P2P (via direct pool) ───────────────────────────────────

  Future<void> _onSendDirectFile(DiscoveredServer device) async {
    if (_transferCtrl.activeTransfer != null) return;

    final conn = await _serverCtrl.getDirectConnection(device.url, _transferCtrl.deviceName);
    if (!mounted) return;
    if (conn == null) {
      _showSnackBar('No se pudo conectar con ${device.appName}', isError: true);
      return;
    }
    if (!conn.targetE2E) {
      _showSnackBar('${device.appName} necesita actualizar SrvFiles para recibir archivos cifrados', isError: true);
      return;
    }

    await _transferCtrl.sendFiles(
      targetClientId: conn.targetClientId,
      peerName: device.appName,
      service: conn.service,
    );
    _serverCtrl.touchPool(device.url);
  }

  // ─── Rename ───────────────────────────────────────────────────────

  Future<void> _renameDevice() async {
    final newName = await NameDialog.show(context, _transferCtrl.deviceName);
    if (newName == null || !mounted) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await _transferCtrl.rename(trimmed);
    _serverCtrl.relay.setDeviceName(_transferCtrl.deviceName);
  }

  // ─── Connect sheet ────────────────────────────────────────────────

  void _showConnectSheet() {
    final cfg = _filesCtrl.config;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConnectSheet(
        currentServerUrl: widget.serverUrl,
        webUrl: (cfg != null && _hasServer && cfg.frontendPort != cfg.port && cfg.lanIp.isNotEmpty)
            ? 'http://${cfg.lanIp}:${cfg.frontendPort}'
            : null,
        relayIp: _serverCtrl.relay.localIp,
        relayPort: _serverCtrl.relay.port,
        relayPin: _serverCtrl.relay.isServerMode ? _serverCtrl.relay.currentPin : null,
        isRelayServer: _serverCtrl.relay.isServerMode,
        isRelayRunning: _serverCtrl.relay.isRunning,
        onConnect: (url) {
          if (mounted) _openServer(url);
        },
        onDisconnect: () {
          if (mounted) _goToSplash();
        },
        onShareLogs: _shareLogs,
      ),
    );
  }

  // ─── Snackbar callback ────────────────────────────────────────────

  void _showSnackBar(String message, {bool isError = false, String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
        duration: actionLabel != null ? const Duration(seconds: 5) : const Duration(seconds: 4),
        action: actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: AppColors.accentPrimary,
                onPressed: onAction ?? () {},
              )
            : null,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // ─── Build ────────────────────────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Se redibuja cuando cambian los archivos o el estado del relay; lo que
    // depende de las transferencias (progreso) tiene su propio builder.
    return ListenableBuilder(
      listenable: Listenable.merge([_filesCtrl, _serverCtrl]),
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filesCtrl.filteredFiles;
    final showServerFiles = _isServer && !_filesCtrl.connectionLost;

    return Scaffold(
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
                  child: Icon(Icons.folder_shared_rounded,
                      color: AppColors.accentPrimary, size: 18),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: GradientText(
                _filesCtrl.config?.appName ?? 'SrvFiles',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: _transferCtrl,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildConnectionIndicator(),
                _buildDeviceNameChip(),
              ],
            ),
          ),
          _buildServerLabel(),
          const SizedBox(width: AppSpacing.sm),
        ],
        bottom: _isServer && _filesCtrl.stats != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: DiskStatsBar(stats: _filesCtrl.stats, fullWidth: true),
              )
            : null,
      ),

      body: _filesCtrl.loading
          ? const SkeletonLoader()
          : _filesCtrl.error != null
              ? _buildError()
              : Column(
                  children: [
                    if (_filesCtrl.connectionLost && _isServer)
                      _buildConnectionBanner(),
                    if (_filesCtrl.downloads.isNotEmpty) _buildDownloadsBanner(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshData,
                        color: AppColors.accentPrimary,
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: ListenableBuilder(
                                listenable: _transferCtrl,
                                builder: (context, _) => OnlineClients(
                                  clients: _transferCtrl.onlineClients,
                                  myClientId: _transferCtrl.myClientId,
                                  activeTransfer: _transferCtrl.activeTransfer,
                                  onSendFile: (clientId, peerName) {
                                    unawaited(_transferCtrl.sendFiles(
                                      targetClientId: clientId,
                                      peerName: peerName,
                                    ));
                                  },
                                  onCancelTransfer: _transferCtrl.cancelTransfer,
                                  onViewServer: _openServer,
                                ),
                              ),
                            ),
                            if (_isDirectMode)
                              SliverToBoxAdapter(child: _buildDirectDevicesSection()),
                            if (showServerFiles) ...[
                              SliverToBoxAdapter(child: _buildToolbar(theme, filtered)),
                              if (filtered.isEmpty)
                                SliverToBoxAdapter(child: _buildEmptyServerFiles(theme))
                              else if (_filesCtrl.isGridView)
                                _buildGrid(filtered)
                              else
                                _buildList(filtered),
                            ],
                            ..._buildReceivedFilesSlivers(theme),
                            if (showServerFiles)
                              SliverToBoxAdapter(child: QrFooter(config: _filesCtrl.config)),
                            const SliverToBoxAdapter(child: SizedBox(height: 80)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

      floatingActionButton: _isServer && !_filesCtrl.loading && _filesCtrl.error == null && !_filesCtrl.connectionLost
          ? FloatingActionButton(
              tooltip: 'Subir archivos',
              onPressed: _filesCtrl.uploading
                  ? _showUploadSheet
                  : () {
                      HapticFeedback.lightImpact();
                      _pickFiles();
                    },
              child: _filesCtrl.uploading
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

  // ─── Sub-build helpers ────────────────────────────────────────────

  /// Estado de la conexión principal: reconectando, cifrada o sin cifrar.
  Widget _buildConnectionIndicator() {
    if (_apiConfig == null) return const SizedBox.shrink();
    final hasOnlinePeers = _transferCtrl.onlineClients
        .where((c) => c.clientId != _transferCtrl.myClientId)
        .isNotEmpty;
    if (!_transferCtrl.isConnected) {
      return const Tooltip(
        message: 'Sin conexión — reconectando…',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Icon(Icons.sync_problem_rounded, size: 16, color: AppColors.danger),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasOnlinePeers)
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.xs),
            child: PulsingDot(size: 8),
          ),
        Tooltip(
          message: _transferCtrl.isEncrypted
              ? 'Conexión cifrada con el servidor/relay'
              : 'Conexión sin cifrar',
          child: Icon(
            _transferCtrl.isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 14,
            color: _transferCtrl.isEncrypted
                ? AppColors.textMuted.withValues(alpha: 0.7)
                : AppColors.danger.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsBanner() {
    return Column(
      children: _filesCtrl.downloads.entries.map((e) {
        final progress = e.value;
        return Container(
          color: AppColors.bgSecondary,
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          child: Row(
            children: [
              const Icon(Icons.download_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress >= 0
                          ? 'Descargando "${e.key}" — ${(progress * 100).round()}%'
                          : 'Descargando "${e.key}"…',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress >= 0 ? progress : null,
                      color: AppColors.accentPrimary,
                      backgroundColor: AppColors.bgGlass,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Cancelar descarga',
                color: AppColors.textMuted,
                onPressed: () => _filesCtrl.cancelDownload(e.key),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDirectDevicesSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _serverCtrl.directDevices.isEmpty && !_serverCtrl.directScanning
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices_rounded,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: AppSpacing.xs),
                      const Text(
                        'Dispositivos en la red',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_serverCtrl.directScanning) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.accentPrimary,
                          ),
                        ),
                      ],
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _serverCtrl.directScanning
                            ? null
                            : () => unawaited(_serverCtrl.scanForDirectDevices()),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Escanear', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ListenableBuilder(
                    listenable: _transferCtrl,
                    builder: (context, _) => Column(
                      children: _serverCtrl.directDevices
                          .map(_buildDirectDeviceRow)
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDirectDeviceRow(DiscoveredServer device) {
    final isSending = _transferCtrl.activeTransfer != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        button: true,
        label: 'Enviar archivos a ${device.appName}',
        child: Material(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: isSending ? null : () => _onSendDirectFile(device),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                        device.isMobile ? Icons.phone_android_rounded : Icons.computer_rounded,
                        color: AppColors.accentPrimary,
                        size: 16),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.appName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          device.ip,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.send_rounded,
                    size: 16,
                    color: isSending
                        ? AppColors.textMuted.withValues(alpha: 0.3)
                        : AppColors.accentPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
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
          const Icon(Icons.wifi_off_rounded, color: AppColors.danger, size: 18),
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
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceNameChip() {
    if (_transferCtrl.deviceName.isEmpty) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Nombre del dispositivo: ${_transferCtrl.deviceName}. Tocar para cambiarlo',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _renameDevice,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_rounded,
                  size: 13,
                  color: AppColors.textMuted.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  _transferCtrl.deviceName,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerLabel() {
    final active = _hasServer || _serverCtrl.relay.isRunning;
    return IconButton(
      tooltip: 'Conexión y servidor',
      onPressed: _showConnectSheet,
      icon: Icon(
        active ? Icons.wifi_rounded : Icons.link_rounded,
        size: 18,
        color: active
            ? AppColors.accentPrimary
            : AppColors.textMuted.withValues(alpha: 0.6),
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
              _filesCtrl.error!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => unawaited(_filesCtrl.initialLoad()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _goToSplash,
              child: const Text('Elegir otro servidor'),
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
                  onChanged: _filesCtrl.setSearchQuery,
                  onClear: () => _filesCtrl.setSearchQuery(''),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildSortMenu(),
              _viewToggleButton(
                icon: Icons.view_list_rounded,
                tooltip: 'Vista de lista',
                active: !_filesCtrl.isGridView,
                onPressed: () { if (_filesCtrl.isGridView) _filesCtrl.toggleGridView(); },
              ),
              _viewToggleButton(
                icon: Icons.grid_view_rounded,
                tooltip: 'Vista de cuadrícula',
                active: _filesCtrl.isGridView,
                onPressed: () { if (!_filesCtrl.isGridView) _filesCtrl.toggleGridView(); },
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
                '${_filesCtrl.searchQuery.isNotEmpty ? ' (filtrando de ${_filesCtrl.files.length})' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortMenu() {
    const labels = {
      FileSort.newest: 'Más recientes',
      FileSort.oldest: 'Más antiguos',
      FileSort.name: 'Nombre (A–Z)',
      FileSort.size: 'Tamaño (mayor primero)',
    };
    return PopupMenuButton<FileSort>(
      tooltip: 'Ordenar',
      icon: const Icon(Icons.sort_rounded, size: 20, color: AppColors.textMuted),
      initialValue: _filesCtrl.sort,
      onSelected: _filesCtrl.setSort,
      itemBuilder: (_) => [
        for (final entry in labels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
    );
  }

  Widget _viewToggleButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
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
              _filesCtrl.searchQuery.isNotEmpty ? '🔍' : '📂',
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _filesCtrl.searchQuery.isNotEmpty
                  ? 'No se encontraron archivos que coincidan con "${_filesCtrl.searchQuery}"'
                  : 'No hay archivos aún',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Encabezado + lista de recibidos como slivers (la lista se construye
  /// de forma perezosa).
  List<Widget> _buildReceivedFilesSlivers(ThemeData theme) {
    return [
      SliverToBoxAdapter(
        child: ValueListenableBuilder<List<FileInfo>>(
          valueListenable: _receivedFiles,
          builder: (context, received, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isServer && _filesCtrl.files.isNotEmpty) ...[
                  const Divider(color: AppColors.borderSubtle, height: 1),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  children: [
                    const Icon(Icons.download_done_rounded,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                    const Text(
                      'Archivos recibidos',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (received.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '(${received.length})',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (received.isEmpty)
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
                  ),
              ],
            ),
          ),
        ),
      ),
      ValueListenableBuilder<List<FileInfo>>(
        valueListenable: _receivedFiles,
        builder: (context, received, _) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final file = received[index];
                return FileListItem(
                  file: file,
                  onDownload: () => OpenFilex.open(file.downloadUrl),
                  onPreview: () => unawaited(PreviewService.previewLocalFile(
                    filePath: file.downloadUrl,
                    fileName: file.name,
                    context: context,
                  )),
                  onShare: () async {
                    await SharePlus.instance.share(ShareParams(files: [XFile(file.downloadUrl)]));
                  },
                  onDelete: () => _deleteReceivedFile(file),
                  downloadIcon: Icons.remove_red_eye_rounded,
                  downloadTooltip: 'Abrir',
                );
              },
              childCount: received.length,
            ),
          ),
        ),
      ),
    ];
  }

  /// Diálogo de confirmación común a recibidos y archivos del servidor.
  Future<bool> _confirmDelete(String fileName, {required bool fromServer}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text(fromServer
            ? '¿Eliminar "$fileName" del servidor?'
            : '¿Eliminar "$fileName"?'),
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
    return confirmed == true;
  }

  Future<void> _deleteReceivedFile(FileInfo file) async {
    if (!await _confirmDelete(file.name, fromServer: false)) return;
    try {
      await _receivedFilesService.deleteFile(file.name);
    } catch (e) {
      AppLogger.instance.error('[Home] delete received file failed', error: e);
      _showSnackBar('No se pudo eliminar "${file.name}"', isError: true);
    }
    await _loadReceivedFiles();
  }

  Future<void> _deleteServerFile(FileInfo file) async {
    if (!await _confirmDelete(file.name, fromServer: true)) return;
    final success = await _filesCtrl.deleteFile(file.name);
    _showSnackBar(
      success ? '"${file.name}" eliminado' : 'No se pudo eliminar "${file.name}"',
      isError: !success,
    );
  }

  void _previewServerFile(BuildContext context, FileInfo file) {
    final service = _filesCtrl.filesService;
    final config = _apiConfig;
    if (service == null || config == null) return;
    unawaited(PreviewService.previewServerFile(
      file: file,
      filesService: service,
      serverUrl: config.baseUrl,
      context: context,
    ));
  }

  SliverList _buildList(List<FileInfo> files) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final file = files[index];
          return FileListItem(
            file: file,
            onDownload: () => _onDownload(file),
            onShare: () => _onShare(file),
            onPreview: () => _previewServerFile(context, file),
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
                  onPreview: () => _previewServerFile(context, file),
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
