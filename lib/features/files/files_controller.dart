import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../config/api_config.dart';
import '../../models/file_info.dart';
import '../../models/disk_stats.dart';
import '../../models/app_config.dart';
import '../../services/files_service.dart';
import '../../services/preview_service.dart';
import '../../services/download_dir_service.dart';
import '../../services/app_logger.dart';
import '../../utils/file_names.dart';

/// Criterio de orden de la lista de archivos del servidor.
enum FileSort { newest, oldest, name, size }

/// Archivo elegido para subir, con su tamaño ya calculado (para no hacer E/S
/// síncrona al dibujar la hoja de subida).
class StagedFile {
  final File file;
  final String name;
  final int size;
  const StagedFile(this.file, this.name, this.size);
}

/// Manages file-related state: listing, upload, download, share, deletion.
class FilesController extends ChangeNotifier {
  FilesController({
    this._filesService,
    this._apiConfig,
    DownloadDirService? downloadDirService,
  }) : _downloadDirService = downloadDirService ?? const DownloadDirService();

  FilesService? _filesService;
  ApiConfig? _apiConfig;
  final DownloadDirService _downloadDirService;
  bool _disposed = false;

  /// Callback para cuando el servidor rechaza el token (pedir el PIN).
  VoidCallback? onAuthRequired;

  // ─── Public state ────────────────────────────────────────────────

  List<FileInfo> files = [];
  DiskStats? stats;
  AppConfig? config;
  bool loading = true;
  String? error;
  bool isGridView = false;
  bool connectionLost = false;
  FileSort sort = FileSort.newest;

  // Upload state
  List<StagedFile> stagedFiles = [];
  bool uploading = false;
  double uploadProgress = 0;
  bool _uploadCancelled = false;

  /// Descargas en curso: nombre → progreso (0–1, o -1 si no se conoce).
  final Map<String, double> downloads = {};
  final Set<String> _cancelledDownloads = {};

  // Search
  String searchQuery = '';
  Timer? _searchDebounce;

  // Temporales creados para "Compartir"; se borran al liberar el controller.
  final List<String> _shareTemps = [];

  // ─── Computed ────────────────────────────────────────────────────

  List<FileInfo> get filteredFiles {
    final query = searchQuery.toLowerCase();
    final list = query.isEmpty
        ? List<FileInfo>.of(files)
        : files.where((f) => f.name.toLowerCase().contains(query)).toList();
    switch (sort) {
      case FileSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case FileSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case FileSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case FileSort.size:
        list.sort((a, b) => b.size.compareTo(a.size));
    }
    return list;
  }

  /// Límite por archivo en bytes, o null si el servidor no impone uno.
  int? get maxFileBytes {
    final mb = config?.maxFileSizeMb ?? 0;
    return mb > 0 ? mb * 1024 * 1024 : null;
  }

  /// Archivos elegidos que superan el límite del servidor.
  List<StagedFile> get oversizedFiles {
    final max = maxFileBytes;
    if (max == null) return const [];
    return stagedFiles.where((f) => f.size > max).toList();
  }

  // ─── Service access ─────────────────────────────────────────────

  FilesService? get filesService => _filesService;
  ApiConfig? get apiConfig => _apiConfig;

  /// Re-initialise the backing service (e.g. when switching servers).
  void setService(FilesService service, ApiConfig config) {
    if (!identical(service, _filesService)) _filesService?.close();
    _filesService = service;
    _apiConfig = config;
    _notify();
  }

  // ─── Data loading ───────────────────────────────────────────────

  Future<void> initialLoad() async {
    final service = _filesService;
    if (service == null) return;
    loading = true;
    error = null;
    _notify();

    try {
      AppLogger.instance.debug('[FilesController] initialLoad starting');
      final results = await Future.wait([
        service.getFiles(),
        service.getStats(),
        service.getConfig(),
      ]);
      if (!identical(service, _filesService)) return; // cambió de servidor

      files = results[0] as List<FileInfo>;
      stats = results[1] as DiskStats;
      config = results[2] as AppConfig;
      loading = false;
      connectionLost = false;
      PreviewService.setMaxPreviewMb(config!.previewMaxFileSizeMb);
      AppLogger.instance.info(
        '[FilesController] initial load complete: ${files.length} files',
      );
      _notify();
    } on AuthRequiredException {
      loading = false;
      _notify();
      onAuthRequired?.call();
    } catch (e) {
      AppLogger.instance.error('[FilesController] initialLoad failed', error: e);
      error = e is ServerException ? e.message : 'No se pudo conectar con el servidor';
      loading = false;
      _notify();
    }
  }

  Future<void> refreshData() async {
    final service = _filesService;
    if (service == null) return;
    try {
      final results = await Future.wait([
        service.getFiles(),
        service.getStats(),
      ]);
      if (!identical(service, _filesService)) return;

      files = results[0] as List<FileInfo>;
      stats = results[1] as DiskStats;
      connectionLost = false;
      error = null;
      _notify();
    } on AuthRequiredException {
      onAuthRequired?.call();
    } catch (e) {
      AppLogger.instance.warn('[FilesController] refreshData failed: $e');
      if (config != null) {
        connectionLost = true;
      } else {
        error = 'No se pudo actualizar la lista';
      }
      _notify();
    }
  }

  // ─── Upload ─────────────────────────────────────────────────────

  Future<List<StagedFile>> pickFiles() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    if (result.isEmpty) return [];

    final picked = <StagedFile>[];
    for (final f in result) {
      final path = f.path;
      if (path == null) continue;
      final file = File(path);
      final size = f.lengthSync();
      picked.add(StagedFile(file, f.name, size != null && size > 0 ? size : await file.length()));
    }

    if (picked.isEmpty) return [];

    stagedFiles = [...stagedFiles, ...picked];
    _notify();
    return picked;
  }

  void removeStagedFile(int index) {
    stagedFiles = List.from(stagedFiles)..removeAt(index);
    _notify();
  }

  void clearStagedFiles() {
    stagedFiles = [];
    _notify();
    unawaited(_clearPickerCache());
  }

  /// Sube los archivos elegidos. Devuelve los nombres que el servidor no pudo
  /// guardar (lista vacía si todo salió bien). Lanza si la subida falla.
  Future<List<String>> uploadStagedFiles() async {
    final service = _filesService;
    if (service == null || stagedFiles.isEmpty) return const [];
    uploading = true;
    uploadProgress = 0;
    _uploadCancelled = false;
    _notify();

    var lastPercent = -1;
    try {
      final failed = await service.uploadFiles(
        stagedFiles.map((s) => s.file).toList(),
        isCancelled: () => _uploadCancelled,
        onProgress: (progress) {
          uploadProgress = progress;
          final percent = (progress * 100).floor();
          if (percent != lastPercent) {
            lastPercent = percent;
            _notify();
          }
        },
      );
      stagedFiles = [];
      unawaited(_clearPickerCache());
      await refreshData();
      return failed;
    } on AuthRequiredException {
      onAuthRequired?.call();
      rethrow;
    } finally {
      uploading = false;
      uploadProgress = 0;
      _notify();
    }
  }

  void cancelUpload() {
    if (!uploading) return;
    _uploadCancelled = true;
  }

  /// Borra las copias que file_picker deja en la caché de la app.
  Future<void> _clearPickerCache() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // No disponible en todas las plataformas.
    }
  }

  // ─── Download ───────────────────────────────────────────────────

  bool isDownloading(String fileName) => downloads.containsKey(fileName);

  /// Downloads a file and returns the local path, or null on error.
  /// Lanza [OperationCancelledException] si el usuario la canceló.
  /// No sobrescribe: si ya existe un archivo con ese nombre usa ` (n)`.
  Future<String?> download(FileInfo file) async {
    final service = _filesService;
    if (service == null || downloads.containsKey(file.name)) return null;
    downloads[file.name] = -1;
    _cancelledDownloads.remove(file.name);
    _notify();
    try {
      final dir = await _downloadDirService.getDownloadsDir();
      final target = await uniqueFileIn(dir, sanitizeFileName(file.name));
      var lastPercent = -1;
      await service.downloadTo(
        file.name,
        target,
        isCancelled: () => _cancelledDownloads.contains(file.name),
        onProgress: (progress) {
          final percent = (progress * 100).floor();
          if (percent != lastPercent) {
            lastPercent = percent;
            downloads[file.name] = progress;
            _notify();
          }
        },
      );
      return target.path;
    } on OperationCancelledException {
      rethrow;
    } on AuthRequiredException {
      onAuthRequired?.call();
      return null;
    } catch (e) {
      AppLogger.instance.error('[FilesController] download failed', error: e);
      return null;
    } finally {
      downloads.remove(file.name);
      _notify();
    }
  }

  void cancelDownload(String fileName) {
    if (downloads.containsKey(fileName)) _cancelledDownloads.add(fileName);
  }

  // ─── Share ──────────────────────────────────────────────────────

  /// Downloads a file to tmp and returns the temp path for sharing.
  Future<String?> prepareShare(FileInfo file) async {
    final service = _filesService;
    if (service == null) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final shareDir = Directory(p.join(tempDir.path, 'srvfiles_share'));
      if (!await shareDir.exists()) await shareDir.create(recursive: true);
      final target = File(p.join(shareDir.path, sanitizeFileName(file.name)));
      await service.downloadTo(file.name, target);
      _shareTemps.add(target.path);
      return target.path;
    } on AuthRequiredException {
      onAuthRequired?.call();
      return null;
    } catch (e) {
      AppLogger.instance.error('[FilesController] prepareShare failed', error: e);
      return null;
    }
  }

  // ─── Delete ─────────────────────────────────────────────────────

  Future<bool> deleteFile(String fileName) async {
    final service = _filesService;
    if (service == null) return false;
    try {
      final ok = await service.deleteFile(fileName);
      if (ok) await refreshData();
      return ok;
    } on AuthRequiredException {
      onAuthRequired?.call();
      return false;
    } catch (e) {
      AppLogger.instance.error('[FilesController] delete failed', error: e);
      return false;
    }
  }

  // ─── Search / view ──────────────────────────────────────────────

  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      searchQuery = query;
      _notify();
    });
  }

  void toggleGridView() {
    isGridView = !isGridView;
    _notify();
  }

  void setSort(FileSort value) {
    sort = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _uploadCancelled = true;
    _cancelledDownloads.addAll(downloads.keys);
    _filesService?.close();
    for (final path in _shareTemps) {
      File(path).delete().catchError((_) => File(path));
    }
    super.dispose();
  }

  // ─── UUID generation ────────────────────────────────────────────

  /// Cryptographically secure transfer ID (UUID v4, 36 caracteres).
  static String generateTransferId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
