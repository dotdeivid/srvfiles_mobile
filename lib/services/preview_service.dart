import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/file_info.dart';
import '../screens/preview_screen.dart';
import '../services/app_logger.dart';
import '../services/files_service.dart';
import '../utils/file_type_helper.dart';
import '../utils/format.dart';

class _PreviewCacheEntry {
  final String path;
  final DateTime _expiresAt;
  _PreviewCacheEntry(this.path) : _expiresAt = DateTime.now().add(const Duration(minutes: 5));
  bool get isValid => DateTime.now().isBefore(_expiresAt);
}

/// Handles opening a file preview.
///
/// Los archivos del servidor se descargan (en streaming) a un temporal que se
/// reutiliza durante 5 minutos si se vuelve a abrir el mismo archivo del mismo
/// servidor; los temporales vencidos se borran en cada uso y todos con
/// [clearCache]. Los archivos locales/recibidos se abren directamente.
class PreviewService {
  PreviewService._();

  static int _maxBytes = 50 * 1024 * 1024; // default 50 MB
  static final Map<String, _PreviewCacheEntry> _cache = {};

  /// Called once the server config is available.
  static void setMaxPreviewMb(int mb) {
    if (mb > 0) _maxBytes = mb * 1024 * 1024;
  }

  // ─── Public API ────────────────────────────────────────────────────

  /// Downloads [file] from the server to a temp path, then opens [PreviewScreen].
  static Future<void> previewServerFile({
    required FileInfo file,
    required FilesService filesService,
    required String serverUrl,
    required BuildContext context,
  }) async {
    if (!FileTypeHelper.canPreview(file.name)) {
      _showCannotPreview(context, file.name);
      return;
    }

    if (file.size > _maxBytes) {
      _showTooBig(context, file);
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    ));

    String tempPath;
    try {
      tempPath = await _downloadToTemp(file, filesService, serverUrl);
    } catch (e, st) {
      AppLogger.instance.error(
        'preview_service.dart: failed to preview server file',
        error: e,
        stack: st,
      );
      navigator.pop(); // dismiss loading
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo previsualizar el archivo')),
      );
      return;
    }

    navigator.pop(); // dismiss loading
    await navigator.push(MaterialPageRoute(
      builder: (_) => PreviewScreen(
        filePath: tempPath,
        fileName: file.name,
      ),
    ));
  }

  /// Opens [PreviewScreen] directly for a file already on disk.
  static Future<void> previewLocalFile({
    required String filePath,
    required String fileName,
    required BuildContext context,
  }) async {
    if (!FileTypeHelper.canPreview(fileName)) {
      _showCannotPreview(context, fileName);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PreviewScreen(
        filePath: filePath,
        fileName: fileName,
      ),
    ));
  }

  /// Borra todos los temporales de previsualización.
  static Future<void> clearCache() async {
    final paths = _cache.values.map((e) => e.path).toList();
    _cache.clear();
    for (final path in paths) {
      await _deleteQuietly(path);
    }
  }

  // ─── Internal ──────────────────────────────────────────────────────

  /// La clave incluye el servidor y la fecha: dos servidores con un archivo
  /// del mismo nombre y tamaño no comparten temporal.
  static String _cacheKey(FileInfo file, String serverUrl) =>
      '$serverUrl|${file.name}|${file.size}|${file.createdAt}';

  static Future<void> _purgeExpired() async {
    final expired = _cache.entries.where((e) => !e.value.isValid).toList();
    for (final e in expired) {
      _cache.remove(e.key);
      await _deleteQuietly(e.value.path);
    }
  }

  static Future<String> _downloadToTemp(
    FileInfo file,
    FilesService filesService,
    String serverUrl,
  ) async {
    await _purgeExpired();
    final key = _cacheKey(file, serverUrl);
    final cached = _cache[key];
    if (cached != null && await File(cached.path).exists()) {
      return cached.path;
    }

    final tempDir = await getTemporaryDirectory();
    final previewDir = Directory(p.join(tempDir.path, 'srvfiles_preview'));
    if (!await previewDir.exists()) await previewDir.create(recursive: true);
    // Nombre único por clave, conservando la extensión para el visor.
    final ext = p.extension(file.name).replaceAll(RegExp(r'[^\w.]'), '');
    final tempFile = File(p.join(previewDir.path, '${key.hashCode.toUnsigned(32)}$ext'));

    await filesService.downloadTo(file.name, tempFile);

    _cache[key] = _PreviewCacheEntry(tempFile.path);
    return tempFile.path;
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static void _showTooBig(BuildContext context, FileInfo file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivo muy grande'),
        content: Text(
          'El archivo es demasiado grande para previsualizar '
          '(${formatBytes(file.size)}). Descargalo para verlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  static void _showCannotPreview(BuildContext context, String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se puede previsualizar "$fileName"')),
    );
  }
}
