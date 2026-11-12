import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../models/disk_stats.dart';
import '../models/app_config.dart';
import 'app_logger.dart';

/// El servidor respondió 401: hay que volver a pedir el PIN.
class AuthRequiredException implements Exception {
  const AuthRequiredException();
  @override
  String toString() => 'Se requiere PIN';
}

/// Error HTTP con un mensaje apto para mostrar al usuario.
class ServerException implements Exception {
  final int statusCode;
  final String message;
  const ServerException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// Operación interrumpida por el usuario.
class OperationCancelledException implements Exception {
  const OperationCancelledException();
}

class FilesService {
  final ApiConfig _config;
  final http.Client _client;
  String? _sessionToken;

  static const _requestTimeout = Duration(seconds: 15);

  /// [client] permite inyectar un cliente en tests. Por defecto se usa uno
  /// propio con keep-alive, compartido por todas las peticiones.
  FilesService(this._config, {http.Client? client}) : _client = client ?? http.Client();

  /// Guarda el token de sesión para incluirlo en todas las requests.
  void setToken(String token) => _sessionToken = token;

  /// Expone el token actual (usado por PreviewService).
  String? get sessionToken => _sessionToken;

  Map<String, String> get _authHeaders =>
      _sessionToken != null ? {'X-SrvFiles-Token': _sessionToken!} : {};

  /// Expone headers de autenticación para uso externo (ej: descargas).
  Map<String, String> get authHeaders => _authHeaders;

  /// Obtiene la lista de archivos del servidor.
  Future<List<FileInfo>> getFiles() async {
    AppLogger.instance.debug('[FilesService] getFiles');
    final response = await _get(_config.filesUrl);
    _check(response, 'obtener archivos');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>?) ?? const [];
    AppLogger.instance.debug('[FilesService] getFiles — ${files.length} files');
    return files
        .whereType<Map<String, dynamic>>()
        .map(FileInfo.fromJson)
        .where((f) => f.name.isNotEmpty)
        .toList();
  }

  /// Sube varios archivos al servidor en una sola petición multipart.
  ///
  /// Los archivos se leen en streaming. [onProgress] recibe la fracción de
  /// bytes enviados (0–1). Si [isCancelled] devuelve true se aborta el envío.
  /// Devuelve los nombres que el servidor no pudo guardar (subida parcial).
  Future<List<String>> uploadFiles(
    List<File> files, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final request = _ProgressMultipartRequest(
      'POST',
      Uri.parse(_config.uploadUrl),
      onProgress: onProgress,
      isCancelled: isCancelled,
    )..headers.addAll(_authHeaders);

    for (final file in files) {
      final fileLength = await file.length();
      request.files.add(
        http.MultipartFile(
          'files',
          file.openRead(),
          fileLength,
          filename: p.basename(file.path),
        ),
      );
    }

    AppLogger.instance.info('[FilesService] uploading ${files.length} files');
    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _client.send(request);
    } on OperationCancelledException {
      rethrow;
    } catch (e) {
      if (isCancelled?.call() ?? false) throw const OperationCancelledException();
      rethrow;
    }
    final response = await http.Response.fromStream(streamedResponse);
    _check(response, 'subir archivos');

    AppLogger.instance.info('[FilesService] uploadFiles complete');
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ((data['failed'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((f) => (f['name'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Descarga [filename] a [target] en streaming. [onProgress] recibe la
  /// fracción descargada si el servidor informa el tamaño.
  Future<void> downloadTo(
    String filename,
    File target, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final request = http.Request('GET', Uri.parse(getDownloadUrl(filename)))
      ..headers.addAll(_authHeaders);
    final response = await _client.send(request).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      _check(http.Response('', response.statusCode), 'descargar el archivo');
    }

    final total = response.contentLength ?? 0;
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) throw const OperationCancelledException();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      await part.rename(target.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Elimina un archivo del servidor.
  Future<bool> deleteFile(String filename) async {
    AppLogger.instance.info('[FilesService] deleteFile: $filename');
    final response = await _client
        .delete(
          Uri.parse('${_config.filesUrl}/${Uri.encodeComponent(filename)}'),
          headers: _authHeaders,
        )
        .timeout(_requestTimeout);
    if (response.statusCode == 401) throw const AuthRequiredException();
    if (response.statusCode != 200) {
      AppLogger.instance.warn('[FilesService] deleteFile failed: status ${response.statusCode}');
    }
    return response.statusCode == 200;
  }

  /// Obtiene estadísticas de uso de disco.
  Future<DiskStats> getStats() async {
    final response = await _get(_config.statsUrl);
    _check(response, 'obtener el espacio en disco');
    return DiskStats.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Obtiene la configuración del servidor.
  Future<AppConfig> getConfig() async {
    final response = await _get(_config.configUrl);
    _check(response, 'obtener la configuración');
    return AppConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Construye la URL de descarga para un archivo (sin hacer request).
  String getDownloadUrl(String filename) => _config.downloadUrl(filename);

  /// Libera el cliente HTTP.
  void close() => _client.close();

  // ─── Internos ──────────────────────────────────────────────────────

  Future<http.Response> _get(String url) =>
      _client.get(Uri.parse(url), headers: _authHeaders).timeout(_requestTimeout);

  void _check(http.Response response, String action) {
    final status = response.statusCode;
    if (status == 200) return;
    AppLogger.instance.error('[FilesService] $action failed', error: 'status $status');
    if (status == 401) throw const AuthRequiredException();
    final message = switch (status) {
      413 => 'El archivo es demasiado grande para el servidor',
      429 => 'Demasiados intentos. Esperá un minuto.',
      404 => 'No se encontró el archivo en el servidor',
      507 => 'El servidor no tiene espacio suficiente',
      >= 500 => 'El servidor tuvo un error al $action',
      _ => 'No se pudo $action (error $status)',
    };
    throw ServerException(status, message);
  }
}

/// MultipartRequest que informa el progreso de los bytes enviados y permite
/// cancelar a mitad de envío.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(
    super.method,
    super.url, {
    this.onProgress,
    this.isCancelled,
  });

  final void Function(double progress)? onProgress;
  final bool Function()? isCancelled;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    var sent = 0;
    var aborted = false;
    final transformed = byteStream.transform<List<int>>(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          if (aborted) return;
          if (isCancelled?.call() ?? false) {
            aborted = true;
            sink.addError(const OperationCancelledException());
            sink.close();
            return;
          }
          sent += data.length;
          if (total > 0) onProgress?.call(sent / total);
          sink.add(data);
        },
      ),
    );
    return http.ByteStream(transformed);
  }
}
