import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'splash_screen.dart';
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../services/files_service.dart';
import '../services/preview_service.dart';
import '../services/transfer_service.dart';
import '../services/device_name_service.dart';
import '../services/notification_service.dart';
import '../services/received_files_service.dart';
import '../services/embedded_relay.dart';
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

  ApiConfig? _apiConfig;
  final _searchController = TextEditingController();

  bool get _hasServer => widget.serverUrl != null;
  bool get _isServer => _hasServer || _serverCtrl.relay.isServerMode;
  bool get _isDirectMode => !_hasServer && !_serverCtrl.relay.isServerMode;

  // Received files (separate from server files)
  List<FileInfo> _receivedFiles = [];

  // ─── Lifecycle ────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _serverCtrl = ServerController(
      relay: EmbeddedRelay(),
      directPool: DirectTransferPool(),
    );

    _filesCtrl = FilesController();

    _transferCtrl = TransferController(
      transferService: TransferService(),
      deviceNameService: DeviceNameService(),
      notificationService: _notificationService,
      receivedFilesService: _receivedFilesService,
      showSnackBar: _showSnackBar,
      showIncomingDialog: (req) => IncomingTransferDialog.show(context, req),
      onAuthRequired: _handleAuthRequired,
      onFilesChanged: _onFilesChanged,
    );

    _initDirectPoolCallbacks();

    if (_hasServer) {
      _apiConfig = ApiConfig(widget.serverUrl!);
      _filesCtrl.setService(FilesService(_apiConfig!), _apiConfig!);
      _initTransfer();
    } else {
      _filesCtrl.loading = false;
      _startRelay();
    }
    _loadReceivedFiles();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _transferCtrl.dispose();
    _serverCtrl.dispose();
    _notificationService.stopForeground();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notificationService.stopForeground();
      if (_apiConfig != null && !_transferCtrl.transferService.isConnected) {
        _connectWebSocket();
      }
    } else if (state == AppLifecycleState.paused) {
      _notificationService.startForeground();
    }
  }

  // ─── Initialisation helpers ───────────────────────────────────────

  Future<void> _startRelay() async {
    final url = await _serverCtrl.startRelay();
    if (url == null) {
      if (mounted) setState(() {});
      return;
    }
    _apiConfig = ApiConfig(url);
    _initTransfer();
    if (widget.autoServerMode) {
      _activateServerMode();
    } else {
      _serverCtrl.startDirectScanning();
    }
  }

  Future<void> _activateServerMode() async {
    try {
      final pin = await _serverCtrl.activateServerMode(
        checkWarning: () async {
          final result = await ServerModeWarningDialog.show(context);
          if (result != true && mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const SplashScreen()),
            );
          }
          return result == true;
        },
        transferService: _transferCtrl.transferService,
        setFilesService: (svc, cfg) {
          _apiConfig = cfg;
          _filesCtrl.setService(svc, cfg);
        },
      );
      if (pin == null) return;
      _connectWebSocket();
      if (mounted) {
        _filesCtrl.loading = true;
        setState(() {});
        await _filesCtrl.initialLoad();
        setState(() {});
      }
    } catch (e) {
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

  void _initTransfer() {
    _transferCtrl.initTransfer().then((_) {
      _serverCtrl.relay.setDeviceName(_transferCtrl.deviceName);
      _connectWebSocket();
    });
  }

  Future<void> _connectWebSocket() async {
    if (_apiConfig == null) return;
    await _transferCtrl.connectWebSocket(
      _apiConfig!,
      hasServer: _hasServer,
      autoServerMode: widget.autoServerMode,
      onAuthOk: () {
        _serverCtrl.relay.setDeviceName(_transferCtrl.deviceName);
        if (_hasServer) _filesCtrl.initialLoad().then((_) => setState(() {}));
      },
    );
  }

  void _initDirectPoolCallbacks() {
    _serverCtrl.initDirectPoolCallbacks(
      onSendRequest: (req) {
        _notificationService.showIncomingTransfer(req.fromName, req.fileName);
        if (mounted) {
          IncomingTransferDialog.show(context, req).then((accepted) {
            if (accepted == true) {
              _transferCtrl.acceptTransfer(req);
            } else {
              _transferCtrl.transferService.reject(req.transferId);
            }
            setState(() {});
          });
        }
      },
      onSendAccept: (id) { _transferCtrl.handleSendAccept(id); setState(() {}); },
      onSendReject: (id, reason) {
        if (_transferCtrl.pendingSend?.transferId == id) {
          _transferCtrl.cancelTransfer();
          setState(() {});
        }
      },
      onSendCancel: (id) {
        _transferCtrl.cancelTransfer();
        setState(() {});
      },
      onSendComplete: (id) async {
        // handled internally by transferCtrl
      },
      onBinaryChunk: (id, data) {
        _transferCtrl.handleBinaryChunk(id, data);
        setState(() {});
      },
    );
  }

  void _handleAuthRequired() {
    if (!mounted) return;
    if (!_hasServer && _serverCtrl.relay.isServerMode && _serverCtrl.relay.currentPin != null) {
      _serverCtrl.autoAuthWithRelay(
        _transferCtrl.transferService,
        _filesCtrl.filesService,
      ).then((ok) {
        if (ok) _connectWebSocket();
      });
    } else {
      _showPinEntryDialog();
    }
  }

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
            _transferCtrl.transferService.setToken(token);
            _filesCtrl.filesService?.setToken(token);
            return null;
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
    _connectWebSocket();
    if (_isServer) _filesCtrl.initialLoad().then((_) => setState(() {}));
  }

  // ─── Data helpers ─────────────────────────────────────────────────

  Future<void> _loadReceivedFiles() async {
    final files = await _receivedFilesService.listFiles();
    if (mounted) setState(() => _receivedFiles = files);
  }

  Future<void> _onFilesChanged() async {
    await _loadReceivedFiles();
    await _filesCtrl.refreshData();
    if (mounted) setState(() {});
  }

  Future<void> _refreshData() async {
    await _loadReceivedFiles();
    await _filesCtrl.refreshData();
    if (mounted) setState(() {});
  }

  // ─── Upload ───────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    final picked = await _filesCtrl.pickFiles();
    if (picked.isNotEmpty) _showUploadSheet();
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return UploadSheet(
            files: _filesCtrl.stagedFiles,
            uploading: _filesCtrl.uploading,
            uploadProgress: _filesCtrl.uploadProgress,
            maxFileSizeMb: _filesCtrl.config?.maxFileSizeMb,
            onRemove: (index) {
              _filesCtrl.removeStagedFile(index);
              setSheetState(() {});
              setState(() {});
              if (_filesCtrl.stagedFiles.isEmpty) Navigator.of(ctx).pop();
            },
            onClearAll: () {
              _filesCtrl.clearStagedFiles();
              setState(() {});
              Navigator.of(ctx).pop();
            },
            onUpload: () async {
              setState(() {});
              setSheetState(() {});
              try {
                await _filesCtrl.uploadStagedFiles();
                setState(() {});
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Archivos subidos correctamente')),
                  );
                }
              } catch (e) {
                setState(() {});
                setSheetState(() {});
                if (mounted) {
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

  // ─── Download / Share ─────────────────────────────────────────────

  Future<void> _onDownload(FileInfo file) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Descargando "${file.name}"...')),
    );
    final filePath = await _filesCtrl.download(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    if (filePath != null) {
      _notificationService.showDownloadComplete(file.name);
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al descargar "${file.name}"'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _onShare(FileInfo file) async {
    final tempPath = await _filesCtrl.prepareShare(file);
    if (tempPath != null) {
      await Share.shareXFiles([XFile(tempPath)]);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al compartir "${file.name}"'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ─── Send P2P (via direct pool) ───────────────────────────────────

  Future<void> _onSendDirectFile(DiscoveredServer device) async {
    if (_transferCtrl.activeTransfer != null) return;

    final conn = await _serverCtrl.getDirectConnection(device.url, _transferCtrl.deviceName);
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

    await _transferCtrl.sendFileViaService(
      targetClientId: conn.targetClientId,
      peerName: device.appName,
      service: conn.service,
    );
    _serverCtrl.touchPool(device.url);
    setState(() {});
  }

  // ─── Rename ───────────────────────────────────────────────────────

  Future<void> _renameDevice() async {
    final newName = await NameDialog.show(context, _transferCtrl.deviceName);
    if (newName == null || !mounted) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await _transferCtrl.rename(trimmed);
    _serverCtrl.relay.setDeviceName(trimmed);
    setState(() {});
  }

  // ─── Connect sheet ────────────────────────────────────────────────

  void _showConnectSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConnectSheet(
        currentServerUrl: widget.serverUrl,
        webUrl: (_filesCtrl.config != null && widget.serverUrl != null && _filesCtrl.config!.frontendPort != _filesCtrl.config!.port)
            ? 'http://${_filesCtrl.config!.lanIp}:${_filesCtrl.config!.frontendPort}'
            : null,
        relayIp: _serverCtrl.relay.localIp,
        relayPort: _serverCtrl.relay.port,
        relayPin: _serverCtrl.relay.isServerMode ? _serverCtrl.relay.currentPin : null,
        isRelayServer: _serverCtrl.relay.isServerMode,
        isRelayRunning: _serverCtrl.relay.isRunning,
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

  // ─── Snackbar callback ────────────────────────────────────────────

  void _showSnackBar(String message, {bool isError = false, String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
    setState(() {});
  }

  // ═════════════════════════════════════════════════════════════════
  // ─── Build ────────────────────────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filesCtrl.filteredFiles;
    final hasOnlinePeers = _transferCtrl.onlineClients
        .where((c) => c.clientId != _transferCtrl.myClientId)
        .isNotEmpty;

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
            GradientText(
              _filesCtrl.config?.appName ?? 'SrvFiles',
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
        actions: [
          if (hasOnlinePeers)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: PulsingDot(size: 8),
            ),
          _buildDeviceNameChip(),
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
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshData,
                        color: AppColors.accentPrimary,
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: OnlineClients(
                                clients: _transferCtrl.onlineClients,
                                myClientId: _transferCtrl.myClientId,
                                activeTransfer: _transferCtrl.activeTransfer,
                                onSendFile: (clientId, peerName) {
                                  _transferCtrl.sendFile(clientId, peerName).then((_) => setState(() {}));
                                },
                                onCancelTransfer: () {
                                  _transferCtrl.cancelTransfer();
                                  setState(() {});
                                },
                                onViewServer: (url) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => HomeScreen(serverUrl: url),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_isDirectMode)
                              SliverToBoxAdapter(child: _buildDirectDevicesSection()),
                            if (_isServer && !_filesCtrl.connectionLost) ...[
                              SliverToBoxAdapter(child: _buildToolbar(theme, filtered)),
                              if (filtered.isEmpty)
                                SliverToBoxAdapter(child: _buildEmptyServerFiles(theme))
                              else if (_filesCtrl.isGridView)
                                _buildGrid(filtered)
                              else
                                _buildList(filtered),
                            ],
                            SliverToBoxAdapter(child: _buildReceivedFilesSection(theme)),
                            if (_isServer && !_filesCtrl.connectionLost)
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
              onPressed: _filesCtrl.uploading
                  ? null
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
                        onPressed: () => _serverCtrl.scanForDirectDevices().then((_) => setState(() {})),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Escanear', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._serverCtrl.directDevices.map(
                    (device) => _buildDirectDeviceRow(device),
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
                  child: const Icon(Icons.phone_android_rounded,
                      color: AppColors.accentPrimary, size: 16),
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
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceNameChip() {
    if (_transferCtrl.deviceName.isEmpty) return const SizedBox.shrink();
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
            Icon(Icons.person_rounded,
                size: 13,
                color: AppColors.textMuted.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text(
              _transferCtrl.deviceName,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerLabel() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _showConnectSheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Icon(
          (_hasServer || _serverCtrl.relay.isRunning)
              ? Icons.wifi_rounded
              : Icons.link_rounded,
          size: 18,
          color: (_hasServer || _serverCtrl.relay.isRunning)
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
              _filesCtrl.error!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => _filesCtrl.initialLoad().then((_) => setState(() {})),
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
                  onChanged: (value) {
                    _filesCtrl.setSearchQuery(value);
                    setState(() {});
                  },
                  onClear: () {
                    _filesCtrl.setSearchQuery('');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _viewToggleButton(
                icon: Icons.view_list_rounded,
                active: !_filesCtrl.isGridView,
                onPressed: () { _filesCtrl.toggleGridView(); setState(() {}); },
              ),
              _viewToggleButton(
                icon: Icons.grid_view_rounded,
                active: _filesCtrl.isGridView,
                onPressed: () { _filesCtrl.toggleGridView(); setState(() {}); },
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

  Widget _buildReceivedFilesSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isServer && _filesCtrl.files.isNotEmpty)
            const Divider(color: AppColors.borderSubtle, height: 1),
          if (_isServer && _filesCtrl.files.isNotEmpty)
            const SizedBox(height: AppSpacing.md),
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
    if (confirmed == true) {
      final success = await _filesCtrl.deleteFile(file.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '"${file.name}" eliminado'
                : 'Error al eliminar "${file.name}"'),
            backgroundColor: success ? null : AppColors.danger,
          ),
        );
        setState(() {});
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
              sessionToken: _filesCtrl.filesService?.sessionToken,
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
                    sessionToken: _filesCtrl.filesService?.sessionToken,
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
