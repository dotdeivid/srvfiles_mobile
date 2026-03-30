import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import '../mobile_server_storage_service.dart';

/// Handles all HTTP REST endpoints for the embedded relay's server mode:
/// file listing, upload, download, delete, stats, config, health.
class RelayHttpHandler {
  MobileServerStorageService? storage;

  /// Callback to notify WS clients that files changed on the server.
  VoidCallback? onFilesChanged;

  // ─── File endpoints ────────────────────────────────────────────────

  Future<void> handleListFiles(HttpRequest req) async {
    final files = await storage!.listFiles();
    final list = files
        .map((f) => {
              'name': f.name,
              'size': f.size,
              'createdAt': f.createdAt,
              'downloadUrl': f.downloadUrl,
            })
        .toList();
    _jsonOk(req, {'files': list, 'count': list.length});
  }

  Future<void> handleUpload(HttpRequest req) async {
    final contentType = req.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    if (boundary == null) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing boundary')
        ..close();
      return;
    }

    final savedNames = <String>[];
    final transformer = MimeMultipartTransformer(boundary);
    final parts = await transformer.bind(req).toList();

    for (final part in parts) {
      final disposition = part.headers['content-disposition'] ?? '';
      final nameMatch = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
      if (nameMatch == null) continue;

      final fileName = nameMatch.group(1)!;
      final bytes = await part.fold<List<int>>([], (a, b) => a..addAll(b));
      final saved = await storage!.saveFile(fileName, bytes);
      savedNames.add(saved);
    }

    _jsonOk(req, {'message': 'Archivos subidos', 'files': savedNames});
    onFilesChanged?.call();
  }

  Future<void> handleDownload(HttpRequest req, String fileName) async {
    final file = await storage!.getFile(fileName);
    if (file == null) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Archivo no encontrado')
        ..close();
      return;
    }
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, mimeType)
      ..headers.set(
        'content-disposition',
        'attachment; filename="${Uri.encodeComponent(fileName)}"',
      );
    await file.openRead().pipe(req.response);
    await req.response.close();
  }

  Future<void> handleDeleteFile(HttpRequest req, String fileName) async {
    await storage!.deleteFile(fileName);
    _jsonOk(req, {'message': 'Eliminado'});
    onFilesChanged?.call();
  }

  Future<void> handleStats(HttpRequest req) async {
    final stats = await storage!.getStats();
    _jsonOk(req, {'total': stats.total, 'used': stats.used, 'free': stats.free});
  }

  void handleConfig(HttpRequest req, {required String? localIp, required int port}) {
    _jsonOk(req, {
      'appName': 'SrvFiles Mobile',
      'lanIp': localIp ?? '',
      'port': port,
      'frontendPort': port,
      'maxFileSizeMb': 0,
      'lanUrl': 'http://${localIp ?? ''}:$port',
    });
  }

  void handleHealth(HttpRequest req, {
    required String? deviceName,
    required bool serverModeActive,
    required int clientCount,
  }) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'status': 'ok',
        'app': 'srvfiles',
        'appName': deviceName ?? 'SrvFiles',
        'relay': true,
        'serverMode': serverModeActive,
        'clients': clientCount,
      }))
      ..close();
  }

  // ─── Static file serving ─────────────────────────────────────────

  Future<void> handleStaticFile(HttpRequest req) async {
    var path = req.uri.path;
    if (path == '/' || path.isEmpty) path = '/index.html';

    final assetPath = 'assets/www$path';
    ByteData? data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (_) {
      try {
        data = await rootBundle.load('assets/www/index.html');
        path = '/index.html';
      } catch (_) {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
        return;
      }
    }

    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final mimeType = _staticMimeType(path);

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, mimeType)
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..add(bytes);
    await req.response.close();
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  void _jsonOk(HttpRequest req, Map<String, dynamic> body) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  static String _staticMimeType(String path) {
    if (path.endsWith('.html')) return 'text/html; charset=utf-8';
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (path.endsWith('.css')) return 'text/css; charset=utf-8';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.ico')) return 'image/x-icon';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.ttf')) return 'font/ttf';
    if (path.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }
}

typedef VoidCallback = void Function();
