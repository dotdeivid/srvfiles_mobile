import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import '../mobile_server_storage_service.dart';

/// Margen de espacio libre que se deja al aceptar una subida.
const _freeSpaceMargin = 50 * 1024 * 1024;

/// Handles all HTTP REST endpoints for the embedded relay's server mode:
/// file listing, upload, download, delete, stats, config, health.
///
/// [storage] puede volverse null si el modo servidor se apaga durante una
/// petición: cada handler lo lee una sola vez y responde 503 si falta.
class RelayHttpHandler {
  MobileServerStorageService? storage;

  /// Callback to notify WS clients that files changed on the server.
  void Function()? onFilesChanged;

  // ─── File endpoints ────────────────────────────────────────────────

  Future<void> handleListFiles(HttpRequest req) async {
    final store = storage;
    if (store == null) return _unavailable(req);
    final files = await store.listFiles();
    final list = files
        .map((f) => {
              'name': f.name,
              'size': f.size,
              'createdAt': f.createdAt,
              'downloadUrl': f.downloadUrl,
            })
        .toList();
    _json(req, HttpStatus.ok, {'files': list, 'count': list.length});
  }

  /// Recibe `multipart/form-data` y escribe cada parte directo a disco, sin
  /// acumular el archivo en memoria.
  Future<void> handleUpload(HttpRequest req) async {
    final store = storage;
    if (store == null) return _unavailable(req);

    final boundary = req.headers.contentType?.parameters['boundary'];
    if (boundary == null) {
      _json(req, HttpStatus.badRequest, {'error': 'Missing boundary'});
      return;
    }

    // Comprobar espacio libre antes de aceptar (si el cliente informa tamaño).
    final declared = req.contentLength;
    if (declared > 0) {
      final free = await getFreeDiskBytes();
      if (free != null && declared + _freeSpaceMargin > free) {
        _json(req, HttpStatus.insufficientStorage,
            {'error': 'No hay espacio suficiente en el dispositivo'});
        return;
      }
    }

    final savedNames = <String>[];
    final failed = <Map<String, String>>[];
    await for (final part in MimeMultipartTransformer(boundary).bind(req)) {
      final disposition = part.headers['content-disposition'] ?? '';
      final fileName = _fileNameFromDisposition(disposition);
      if (fileName == null) {
        await part.drain<void>();
        continue;
      }
      try {
        savedNames.add(await store.saveStream(fileName, part));
      } catch (e) {
        failed.add({'name': fileName, 'reason': 'No se pudo guardar'});
        await part.drain<void>().catchError((_) {});
      }
    }

    if (savedNames.isEmpty && failed.isNotEmpty) {
      _json(req, HttpStatus.internalServerError,
          {'error': 'No se pudo guardar ningún archivo', 'failed': failed});
      return;
    }
    _json(req, HttpStatus.ok, {
      'message': 'Archivos subidos',
      'files': savedNames,
      if (failed.isNotEmpty) 'failed': failed,
    });
    if (savedNames.isNotEmpty) onFilesChanged?.call();
  }

  /// POST /api/files/link {"name": "..."} → {"token", "expiresIn"}: token de
  /// enlace para descargar o previsualizar solo ese archivo por unos minutos.
  Future<void> handleLink(HttpRequest req, String Function(String fileName) createToken) async {
    final store = storage;
    if (store == null) return _unavailable(req);
    String? name;
    try {
      final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      name = body['name'] as String?;
    } catch (_) {}
    if (name == null || await store.getFile(name) == null) {
      _json(req, HttpStatus.notFound, {'error': 'Archivo no encontrado'});
      return;
    }
    _json(req, HttpStatus.ok, {'token': createToken(name), 'expiresIn': 600});
  }

  /// Descarga ([inline] = false) o vista previa ([inline] = true).
  ///
  /// En la vista previa, HTML/XML/JS se sirven como texto plano y todo menos
  /// el PDF lleva CSP sandbox: un archivo subido no puede ejecutar scripts.
  Future<void> handleDownload(HttpRequest req, String fileName, {bool inline = false}) async {
    final store = storage;
    if (store == null) return _unavailable(req);
    final file = await store.getFile(fileName);
    if (file == null) {
      _json(req, HttpStatus.notFound, {'error': 'Archivo no encontrado'});
      return;
    }
    final length = await file.length();
    var mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    final res = req.response;
    if (inline && RegExp(r'html|xml|javascript').hasMatch(mimeType)) {
      mimeType = 'text/plain; charset=utf-8';
    }
    res.headers
      ..set(HttpHeaders.contentTypeHeader, mimeType)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('content-disposition', _contentDisposition(fileName, inline: inline));
    if (!mimeType.startsWith('application/pdf')) {
      res.headers.set('Content-Security-Policy',
          "sandbox; default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'");
    }

    // Soporte básico de Range (un solo rango) para reanudar y para video.
    final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader), length);
    if (range != null) {
      res
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.start}-${range.end}/$length')
        ..contentLength = range.end - range.start + 1;
      await res.addStream(file.openRead(range.start, range.end + 1));
    } else {
      res
        ..statusCode = HttpStatus.ok
        ..contentLength = length;
      await res.addStream(file.openRead());
    }
    await res.close();
  }

  Future<void> handleDeleteFile(HttpRequest req, String fileName) async {
    final store = storage;
    if (store == null) return _unavailable(req);
    final deleted = await store.deleteFile(fileName);
    if (!deleted) {
      _json(req, HttpStatus.notFound, {'error': 'Archivo no encontrado'});
      return;
    }
    _json(req, HttpStatus.ok, {'message': 'Eliminado'});
    onFilesChanged?.call();
  }

  Future<void> handleStats(HttpRequest req) async {
    final store = storage;
    if (store == null) return _unavailable(req);
    final stats = await store.getStats();
    _json(req, HttpStatus.ok, {'total': stats.total, 'used': stats.used, 'free': stats.free});
  }

  void handleConfig(HttpRequest req, {required String? localIp, required int port}) {
    _json(req, HttpStatus.ok, {
      'appName': 'SrvFiles Mobile',
      'lanIp': localIp ?? '',
      'port': port,
      'frontendPort': port,
      // 0 = sin límite por archivo (el límite real es el espacio libre).
      'maxFileSizeMb': 0,
      'lanUrl': localIp != null ? 'http://$localIp:$port' : '',
    });
  }

  void handleHealth(HttpRequest req, {
    required String? deviceName,
    required bool serverModeActive,
    required int clientCount,
    required int port,
  }) {
    _json(req, HttpStatus.ok, {
      'status': 'ok',
      'app': 'srvfiles',
      'appName': deviceName ?? 'SrvFiles',
      'relay': true,
      'serverMode': serverModeActive,
      'deviceType': 'mobile',
      'port': port,
      'clients': clientCount,
    });
  }

  // ─── Static file serving ─────────────────────────────────────────

  Future<void> handleStaticFile(HttpRequest req) async {
    var path = req.uri.path;
    if (path == '/' || path.isEmpty) path = '/index.html';
    if (path.contains('..')) path = '/index.html';

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
          ..write('Not found');
        await req.response.close();
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

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  void _unavailable(HttpRequest req) => _json(
      req, HttpStatus.serviceUnavailable, {'error': 'Modo servidor inactivo'});

  /// Extrae el nombre de archivo de `Content-Disposition`, aceptando tanto
  /// `filename="…"` como `filename*=UTF-8''…`.
  static String? _fileNameFromDisposition(String disposition) {
    final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(disposition);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {}
    }
    final plain = RegExp(r'filename="([^"]*)"').firstMatch(disposition);
    final name = plain?.group(1);
    if (name == null || name.isEmpty) return null;
    // Los navegadores mandan el nombre en UTF-8, pero el parser multipart
    // decodifica las cabeceras como Latin-1 ("año" llega como "aÃ±o").
    try {
      return utf8.decode(latin1.encode(name));
    } catch (_) {
      return name;
    }
  }

  /// `attachment` con nombre ASCII de respaldo y `filename*` en UTF-8 (RFC 6266).
  static String _contentDisposition(String fileName, {bool inline = false}) {
    final ascii = fileName.replaceAll(RegExp(r'[^\x20-\x7e]|["\\]'), '_');
    return '${inline ? 'inline' : 'attachment'}; filename="$ascii"; '
        "filename*=UTF-8''${Uri.encodeComponent(fileName)}";
  }

  static ({int start, int end})? _parseRange(String? header, int length) {
    if (header == null || length == 0) return null;
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return null;
    final startStr = m.group(1)!;
    final endStr = m.group(2)!;
    int start;
    int end;
    if (startStr.isEmpty) {
      if (endStr.isEmpty) return null;
      final suffix = int.parse(endStr);
      start = (length - suffix).clamp(0, length - 1);
      end = length - 1;
    } else {
      start = int.parse(startStr);
      end = endStr.isEmpty ? length - 1 : int.parse(endStr).clamp(0, length - 1);
    }
    if (start > end || start >= length) return null;
    return (start: start, end: end);
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
