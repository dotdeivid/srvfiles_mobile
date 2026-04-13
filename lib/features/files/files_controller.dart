import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/api_config.dart';
import '../../models/file_info.dart';
import '../../models/disk_stats.dart';
import '../../models/app_config.dart';
import '../../services/files_service.dart';
import '../../services/preview_service.dart';
import '../../services/download_dir_service.dart';
import '../../services/app_logger.dart';

/// Manages file-related state: listing, upload, download, share, deletion.
///
/// Replaces the file-related `setState()` calls and methods that lived in
/// `_HomeScreenState` (home_screen.dart L446–1055).
class FilesController extends ChangeNotifier {
  FilesController({
    FilesService? filesService,
    ApiConfig? apiConfig,
    DownloadDirService? downloadDirService,
  })  : _filesService = filesService,
        _apiConfig = apiConfig,
        _downloadDirService = downloadDirService ?? const DownloadDirService();

  FilesService? _filesService;
  ApiConfig? _apiConfig;
  final DownloadDirService _downloadDirService;

  // ─── Public state ────────────────────────────────────────────────

  List<FileInfo> files = [];
  DiskStats? stats;
  AppConfig? config;
  bool loading = true;
  String? error;
  bool isGridView = false;
  bool connectionLost = false;

  // Upload state
  List<File> stagedFiles = [];
  bool uploading = false;
  double uploadProgress = 0;

  // Search
  String searchQuery = '';
  Timer? _searchDebounce;

  // ─── Computed ────────────────────────────────────────────────────

  List<FileInfo> get filteredFiles {
    if (searchQuery.isEmpty) return files;
    final query = searchQuery.toLowerCase();
    return files.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  // ─── Service access ─────────────────────────────────────────────

  FilesService? get filesService => _filesService;
  ApiConfig? get apiConfig => _apiConfig;

  /// Re-initialise the backing service (e.g. when switching servers).
  void setService(FilesService service, ApiConfig config) {
    _filesService = service;
    _apiConfig = config;
    notifyListeners();
  }

  // ─── Data loading ───────────────────────────────────────────────

  Future<void> initialLoad() async {
    if (_filesService == null) return;
    loading = true;
    error = null;
    notifyListeners();

    try {
      AppLogger.instance.debug('[FilesController] initialLoad starting');
      final results = await Future.wait([
        _filesService!.getFiles(),
        _filesService!.getStats(),
        _filesService!.getConfig(),
      ]);

      files = results[0] as List<FileInfo>;
      stats = results[1] as DiskStats;
      config = results[2] as AppConfig;
      loading = false;
      PreviewService.setMaxPreviewMb(config!.previewMaxFileSizeMb);
      AppLogger.instance.info(
        '[FilesController] initial load complete: ${files.length} files',
      );
      notifyListeners();
    } catch (e) {
      AppLogger.instance.error('[FilesController] initialLoad failed', error: e);
      error = 'Error al conectar con el servidor';
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshData() async {
    if (_filesService == null) return;
    try {
      final results = await Future.wait([
        _filesService!.getFiles(),
        _filesService!.getStats(),
      ]);

      files = results[0] as List<FileInfo>;
      stats = results[1] as DiskStats;
      connectionLost = false;
      notifyListeners();
    } catch (e) {
      AppLogger.instance.warn('[FilesController] refreshData failed: $e');
      if (files.isNotEmpty) {
        connectionLost = true;
      } else {
        error = 'Error al actualizar datos';
      }
      notifyListeners();
    }
  }

  // ─── Upload ─────────────────────────────────────────────────────

  Future<List<File>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return [];

    final picked = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (picked.isEmpty) return [];

    stagedFiles = [...stagedFiles, ...picked];
    notifyListeners();
    return picked;
  }

  void removeStagedFile(int index) {
    stagedFiles = List.from(stagedFiles)..removeAt(index);
    notifyListeners();
  }

  void clearStagedFiles() {
    stagedFiles = [];
    notifyListeners();
  }

  Future<void> uploadStagedFiles() async {
    if (_filesService == null) return;
    uploading = true;
    uploadProgress = 0;
    notifyListeners();

    try {
      await _filesService!.uploadFiles(stagedFiles);
      uploading = false;
      uploadProgress = 0;
      stagedFiles = [];
      notifyListeners();
      await refreshData();
    } catch (e) {
      uploading = false;
      uploadProgress = 0;
      notifyListeners();
      rethrow;
    }
  }

  // ─── Download ───────────────────────────────────────────────────

  /// Downloads a file and returns the local path, or null on error.
  Future<String?> download(FileInfo file) async {
    if (_filesService == null) return null;
    try {
      final url = _filesService!.getDownloadUrl(file.name);
      final response = await http.get(
        Uri.parse(url),
        headers: _filesService!.authHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Status ${response.statusCode}');
      }

      final dir = await _downloadDirService.getDownloadsDir();
      final filePath = '${dir.path}/${file.name}';
      await File(filePath).writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      AppLogger.instance.error('[FilesController] download failed', error: e);
      return null;
    }
  }

  // ─── Share ──────────────────────────────────────────────────────

  /// Downloads a file to tmp and returns the temp path for sharing.
  Future<String?> prepareShare(FileInfo file) async {
    if (_filesService == null) return null;
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
      return tempPath;
    } catch (e) {
      AppLogger.instance.error('[FilesController] prepareShare failed', error: e);
      return null;
    }
  }

  // ─── Delete ─────────────────────────────────────────────────────

  Future<bool> deleteFile(String fileName) async {
    if (_filesService == null) return false;
    try {
      await _filesService!.deleteFile(fileName);
      await refreshData();
      return true;
    } catch (e) {
      AppLogger.instance.error('[FilesController] delete failed', error: e);
      return false;
    }
  }

  // ─── Search ─────────────────────────────────────────────────────

  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      searchQuery = query;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void toggleGridView() {
    isGridView = !isGridView;
    notifyListeners();
  }

  // ─── UUID generation ────────────────────────────────────────────

  /// Cryptographically secure transfer ID (replaces old DateTime-based impl).
  static String generateTransferId() {
    final rng = Random.secure();
    String hex(int count) =>
        List.generate(count, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '${hex(4)}-${hex(2)}-4${hex(1).substring(1)}${hex(1)}-${(0x80 | rng.nextInt(0x40)).toRadixString(16)}${hex(1)}-${hex(6)}';
  }
}
