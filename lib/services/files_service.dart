import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/file_info.dart';
import '../models/disk_stats.dart';
import '../models/app_config.dart';

class FilesService {
  final ApiConfig _config;

  FilesService(this._config);

  /// Obtiene la lista de archivos del servidor.
  Future<List<FileInfo>> getFiles() async {
    final response = await http.get(Uri.parse(_config.filesUrl));
    if (response.statusCode != 200) {
      throw Exception('Error al obtener archivos: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>;
    return files
        .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sube un archivo al servidor con callback de progreso.
  Future<void> uploadFile(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_config.uploadUrl),
    );
    final fileLength = await file.length();
    request.files.add(
      http.MultipartFile(
        'files',
        file.openRead(),
        fileLength,
        filename: file.path.split('/').last,
      ),
    );

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != 200) {
      throw Exception('Error al subir archivo: ${streamedResponse.statusCode}');
    }

    // Consumir el response body
    await streamedResponse.stream.drain();
  }

  /// Sube múltiples archivos al servidor.
  Future<void> uploadFiles(
    List<File> files, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_config.uploadUrl),
    );

    for (final file in files) {
      final fileLength = await file.length();
      request.files.add(
        http.MultipartFile(
          'files',
          file.openRead(),
          fileLength,
          filename: file.path.split('/').last,
        ),
      );
    }

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != 200) {
      throw Exception('Error al subir archivos: ${streamedResponse.statusCode}');
    }

    await streamedResponse.stream.drain();
  }

  /// Elimina un archivo del servidor.
  Future<bool> deleteFile(String filename) async {
    final response = await http.delete(
      Uri.parse('${_config.filesUrl}/${Uri.encodeComponent(filename)}'),
    );
    return response.statusCode == 200;
  }

  /// Obtiene estadísticas de uso de disco.
  Future<DiskStats> getStats() async {
    final response = await http.get(Uri.parse(_config.statsUrl));
    if (response.statusCode != 200) {
      throw Exception('Error al obtener stats: ${response.statusCode}');
    }
    return DiskStats.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Obtiene la configuración del servidor.
  Future<AppConfig> getConfig() async {
    final response = await http.get(Uri.parse(_config.configUrl));
    if (response.statusCode != 200) {
      throw Exception('Error al obtener config: ${response.statusCode}');
    }
    return AppConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Construye la URL de descarga para un archivo (sin hacer request).
  String getDownloadUrl(String filename) => _config.downloadUrl(filename);

  /// Verifica si el servidor está accesible.
  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(Uri.parse(_config.healthUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
