import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../models/disk_stats.dart';
import '../models/app_config.dart';
import '../models/transfer_client.dart';
import '../models/transfer_request.dart';
import '../models/active_transfer.dart';
import '../services/files_service.dart';
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
import '../widgets/pulsing_dot.dart';
import '../widgets/skeleton_loader.dart';
import '../services/notification_service.dart';
import '../services/received_files_service.dart';
import '../services/embedded_relay.dart';
import '../services/discovery_service.dart';

/// Intervalo de polling (mismo que el frontend web: 5 segundos).
const _pollInterval = Duration(seconds: 5);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.serverUrl});

  /// URL del servidor. Si es null, la app entra en modo sin servidor
  /// (solo P2P + archivos recibidos).
  final String? serverUrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilesService? _filesService;
  ApiConfig? _apiConfig;

  /// true si estamos en modo servidor (conectados a un server HTTP).
  bool get _hasServer => widget.serverUrl != null;

  List<FileInfo> _files = [];
  DiskStats? _stats;
  AppConfig? _config;
  bool _loading = true;
  String? _error;
  bool _isGridView = false;
  Timer? _pollTimer;

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

  @override
  void initState() {
    super.initState();
    if (_hasServer) {
      _apiConfig = ApiConfig(widget.serverUrl!);
      _filesService = FilesService(_apiConfig!);
      _initialLoad();
      _startPolling();
      _initTransfer();
    } else {
      // Modo sin servidor: levantar relay, luego conectarse como cliente
      _loading = false;
      _startRelay();
    }
    _loadReceivedFiles();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchController.dispose();
    _transferService.dispose();
    _relay.stop();
    super.dispose();
  }

  // ─── Relay embebido ────────────────────────────────────────────────

  Future<void> _startRelay() async {
    try {
      await _relay.start();
      // Conectar el TransferService al relay propio
      _apiConfig = ApiConfig(_relay.url!);
      _initTransfer();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo iniciar el relay: $e');
      }
    }
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
      final results = await Future.wait([
        _filesService!.getFiles(),
        _filesService!.getStats(),
        _filesService!.getConfig(),
      ]);

      if (mounted) {
        setState(() {
          _files = results[0] as List<FileInfo>;
          _stats = results[1] as DiskStats;
          _config = results[2] as AppConfig;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] _initialLoad error → $e');
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
      if (mounted && _files.isNotEmpty) {
        // Si ya tenemos datos, mostrar banner en vez de error completo
        setState(() => _connectionLost = true);
      } else if (mounted) {
        setState(() => _error = 'Error al actualizar datos');
      }
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      // No hacer polling si el cargado inicial ya falló
      if (_error != null) return;
      _refreshData();
    });
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

    _connectWebSocket();
  }

  void _connectWebSocket() {
    if (_apiConfig == null) return;
    _transferService.connect(_apiConfig!);
    _transferService.register(_deviceName);
    _transferService.setReceiving(true);
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

    await _transferService.sendFile(
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
      if (_hasServer) await _refreshData();
    }
  }

  // ─── Cancelar transferencia ───────────────────────────────────────

  void _cancelTransfer() {
    final transfer = _activeTransfer;
    if (transfer == null) return;

    _transferService.cancel(transfer.transferId);
    _receiveBuffers.remove(transfer.transferId);
    _pendingSend = null;

    setState(() => _activeTransfer = null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transferencia cancelada')),
    );
  }

  // ─── Utilidades ───────────────────────────────────────────────────

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
      final response = await http.get(Uri.parse(url));

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
    final baseDir = await getApplicationDocumentsDirectory();
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
      final response = await http.get(Uri.parse(url));

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
        onConnect: (url) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(serverUrl: url)),
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
          // Label de servidor tappable
          _buildServerLabel(),
          const SizedBox(width: AppSpacing.sm),
        ],
        // Disk stats ocupa el 100% del ancho debajo del título y la IP
        bottom: _hasServer && _stats != null
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
                    if (_connectionLost && _hasServer)
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

                      // ─── Modo servidor: archivos del server ─────
                      // Se ocultan cuando se pierde la conexión
                      if (_hasServer && !_connectionLost) ...[
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
                      if (_hasServer && !_connectionLost)
                        SliverToBoxAdapter(child: QrFooter(config: _config)),

                      // Espacio inferior para no tapar con FAB
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
                )),
                  ],
                ),

      // ─── FAB upload — solo en modo servidor ──────────────────────
      floatingActionButton: _hasServer && !_loading && _error == null && !_connectionLost
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

  Widget _buildServerLabel() {
    if (_hasServer) {
      // Modo conectado: mostrar IP con ícono verde
      final displayUrl = widget.serverUrl!
          .replaceAll('http://', '')
          .replaceAll('https://', '');
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showConnectDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accentPrimary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                displayUrl,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Modo sin servidor: label tappable para conectar
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showConnectDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _relay.isRunning ? Icons.wifi_tethering_rounded : Icons.link_rounded,
                size: 14,
                color: _relay.isRunning
                    ? AppColors.accentPrimary.withValues(alpha: 0.6)
                    : AppColors.textMuted.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                _relay.isRunning
                    ? '${_relay.localIp ?? '...'}:${_relay.port}'
                    : 'Conectar servidor',
                style: TextStyle(
                  color: _relay.isRunning
                      ? AppColors.textMuted
                      : AppColors.textMuted.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontFamily: _relay.isRunning ? 'monospace' : null,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppColors.textMuted.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      );
    }
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
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Subí archivos desde tu PC o tocá el botón +',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
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
          if (_hasServer && _files.isNotEmpty)
            const Divider(color: AppColors.borderSubtle, height: 1),
          if (_hasServer && _files.isNotEmpty)
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

  SliverList _buildList(List<FileInfo> files) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final file = files[index];
          return FileListItem(
            file: file,
            onDownload: () => _onDownload(file),
            onShare: () => _onShare(file),
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

  const _PendingSend({
    required this.transferId,
    required this.file,
    required this.peerId,
  });
}

// ─── Bottom sheet de conexión a servidor ──────────────────────────────

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.onConnect, this.currentServerUrl});

  final void Function(String url) onConnect;
  final String? currentServerUrl;

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
    _scan();
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

  Widget _buildCurrentServerTile(String serverUrl, ThemeData theme) {
    final displayIp = serverUrl
        .replaceAll('http://', '')
        .replaceAll('https://', '');
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.computer_rounded,
          color: AppColors.accentPrimary,
          size: 18,
        ),
      ),
      title: Text(
        displayIp,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Conectado',
          style: TextStyle(
            color: AppColors.accentPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Excluir el servidor ya conectado de la lista escaneada
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
            child: Text('Conectar a servidor', style: theme.textTheme.titleMedium),
          ),

          // Servidor actual (no clickeable, "Ya conectado")
          if (widget.currentServerUrl != null) ...[
            _buildCurrentServerTile(widget.currentServerUrl!, theme),
            const Divider(
              color: AppColors.borderSubtle,
              indent: AppSpacing.lg,
              endIndent: AppSpacing.lg,
              height: 1,
            ),
          ],

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
      ),
    );
  }
}
