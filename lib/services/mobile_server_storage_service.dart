import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_info.dart';
import '../models/disk_stats.dart';

const _diskChannel = MethodChannel('com.srvfiles/disk_space');

/// Gestiona el directorio de archivos del servidor móvil.
/// Los archivos se guardan en Documents/SrvFiles/server/.
/// Separado de ReceivedFilesService para diferenciarlos visualmente.
class MobileServerStorageService {
  Directory? _dir;

  /// Obtiene (y crea si no existe) el directorio del servidor.
  Future<Directory> getDirectory() async {
    if (_dir != null) return _dir!;
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/SrvFiles/server');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// Lista los archivos ordenados por fecha de modificación (más reciente primero).
  Future<List<FileInfo>> listFiles() async {
    final dir = await getDirectory();
    if (!await dir.exists()) return [];

    final entities = dir.listSync().whereType<File>().toList();
    entities.sort((a, b) {
      return b.statSync().modified.compareTo(a.statSync().modified);
    });

    return entities.map((file) {
      final stat = file.statSync();
      final name = file.path.split('/').last;
      return FileInfo(
        name: name,
        size: stat.size,
        createdAt: stat.modified.toIso8601String(),
        downloadUrl: '/api/files/download/${Uri.encodeComponent(name)}',
      );
    }).toList();
  }

  /// Guarda bytes en el directorio del servidor. Retorna el nombre final del archivo.
  Future<String> saveFile(String fileName, List<int> bytes) async {
    final dir = await getDirectory();
    final sanitized = _sanitize(fileName);
    var target = File('${dir.path}/$sanitized');

    if (await target.exists()) {
      final ext = sanitized.contains('.') ? '.${sanitized.split('.').last}' : '';
      final base =
          ext.isNotEmpty ? sanitized.substring(0, sanitized.length - ext.length) : sanitized;
      var i = 1;
      while (await target.exists()) {
        target = File('${dir.path}/$base ($i)$ext');
        i++;
      }
    }

    await target.writeAsBytes(bytes);
    return target.path.split('/').last;
  }

  /// Elimina un archivo por nombre.
  Future<void> deleteFile(String fileName) async {
    final dir = await getDirectory();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) await file.delete();
  }

  /// Retorna el path completo de un archivo por nombre. Null si no existe.
  Future<File?> getFile(String fileName) async {
    final dir = await getDirectory();
    final file = File('${dir.path}/$fileName');
    return await file.exists() ? file : null;
  }

  /// Calcula el espacio usado en el directorio y el espacio disponible del sistema.
  Future<DiskStats> getStats() async {
    final dir = await getDirectory();
    int used = 0;
    if (await dir.exists()) {
      for (final entity in dir.listSync().whereType<File>()) {
        used += entity.statSync().size;
      }
    }

    int total = 0;
    int free = 0;
    try {
      final freeMb = await _diskChannel.invokeMethod<double>('getFreeDiskSpace');
      final totalMb = await _diskChannel.invokeMethod<double>('getTotalDiskSpace');
      free = ((freeMb ?? 0) * 1024 * 1024).round();
      total = ((totalMb ?? 0) * 1024 * 1024).round();
    } catch (_) {}

    return DiskStats(total: total, used: used, free: free);
  }

  /// Sanitiza el nombre de archivo: elimina path traversal y caracteres no válidos.
  String _sanitize(String name) {
    var result = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    result = result.replaceAll(RegExp(r'\.{2,}'), '_');
    result = result.trim();
    return result.isEmpty ? 'archivo' : result;
  }
}
