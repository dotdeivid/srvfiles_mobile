import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../screens/preview_screen.dart';
import '../services/app_logger.dart';
import '../utils/file_type_helper.dart';
import '../utils/format.dart';

/// Handles opening a file preview.
/// Server files are downloaded to a temp path and cleaned up on close.
/// Local/received files are opened directly.
class PreviewService {
  PreviewService._();

  static int _maxBytes = 50 * 1024 * 1024; // default 50 MB

  /// Called once the server config is available.
  static void setMaxPreviewMb(int mb) => _maxBytes = mb * 1024 * 1024;

  // ─── Public API ────────────────────────────────────────────────────

  /// Downloads [file] from the server to a temp path, then opens [PreviewScreen].
  static Future<void> previewServerFile({
    required FileInfo file,
    required ApiConfig config,
    required String? sessionToken,
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

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final tempPath = await _downloadToTemp(file, config, sessionToken);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PreviewScreen(
          filePath: tempPath,
          fileName: file.name,
          isTempFile: true,
        ),
      ));
    } catch (e, st) {
      AppLogger.instance.error(
        'preview_service.dart: failed to preview server file',
        error: e,
        stack: st,
      );
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo previsualizar el archivo')),
        );
      }
    }
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
        isTempFile: false,
      ),
    ));
  }

  // ─── Internal ──────────────────────────────────────────────────────

  static Future<String> _downloadToTemp(
    FileInfo file,
    ApiConfig config,
    String? sessionToken,
  ) async {
    final url = config.downloadUrl(file.name);
    final headers = sessionToken != null
        ? {'X-SrvFiles-Token': sessionToken}
        : <String, String>{};

    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final tempDir = await getTemporaryDirectory();
    final safeName = file.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final tempFile = File('${tempDir.path}/srvfiles_preview_$safeName');
    await tempFile.writeAsBytes(response.bodyBytes);
    return tempFile.path;
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
