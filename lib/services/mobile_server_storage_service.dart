import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/file_info.dart';
import '../models/disk_stats.dart';
import '../utils/file_names.dart';
import 'app_logger.dart';
import 'download_dir_service.dart';

const _diskChannel = MethodChannel('com.srvfiles/disk_space');

/// Lista los archivos de [dir] ordenados por fecha de modificación (más
/// reciente primero), con E/S asíncrona. [urlFor] construye `downloadUrl`.
Future<List<FileInfo>> listFilesIn(
  Directory dir,
  String Function(File file, String name) urlFor,
) async {
  if (!await dir.exists()) return [];
  final entries = <({File file, FileStat stat})>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    // Ocultos, de sistema y subidas o recepciones en curso (.part).
    if (isHiddenFileName(p.basename(entity.path))) continue;
    entries.add((file: entity, stat: await entity.stat()));
  }
  entries.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
  return entries.map((e) {
    final name = p.basename(e.file.path);
    return FileInfo(
      name: name,
      size: e.stat.size,
      createdAt: e.stat.modified.toIso8601String(),
      downloadUrl: urlFor(e.file, name),
    );
  }).toList();
}

/// Espacio libre del dispositivo en bytes, o null si no se pudo obtener.
Future<int?> getFreeDiskBytes() async {
  try {
    final freeMb = await _diskChannel.invokeMethod<double>('getFreeDiskSpace');
    return freeMb == null ? null : (freeMb * 1024 * 1024).round();
  } catch (e) {
    AppLogger.instance.warn('[Storage] could not get free disk space: $e');
    return null;
  }
}

/// Gestiona los archivos que comparte el modo servidor del teléfono: la
/// carpeta compartida `Download/SrvFiles` (ver [DownloadDirService]), la misma
/// de las descargas y los archivos recibidos.
class MobileServerStorageService {
  Directory? _dir;

  MobileServerStorageService();

  /// Constructor para inyectar directorio en tests.
  @visibleForTesting
  MobileServerStorageService.forTesting(Directory dir) : _dir = dir;

  /// Obtiene (y crea si no existe) el directorio del servidor.
  Future<Directory> getDirectory() async {
    if (_dir != null) return _dir!;
    return _dir = await const DownloadDirService().getDownloadsDir();
  }

  /// Lista los archivos ordenados por fecha de modificación (más reciente primero).
  Future<List<FileInfo>> listFiles() async {
    final dir = await getDirectory();
    return listFilesIn(
      dir,
      (_, name) => '/api/files/download/${Uri.encodeComponent(name)}',
    );
  }

  /// Guarda bytes en el directorio del servidor. Retorna el nombre final del archivo.
  Future<String> saveFile(String fileName, List<int> bytes) =>
      saveStream(fileName, Stream.value(bytes));

  /// Guarda un stream en el directorio del servidor sin cargarlo en memoria.
  /// Escribe primero a `<nombre>.part` y renombra al terminar, para que un
  /// archivo a medio subir no aparezca en la lista. Retorna el nombre final.
  Future<String> saveStream(String fileName, Stream<List<int>> data) async {
    File? partFile;
    try {
      final dir = await getDirectory();
      final target = await uniqueFileIn(dir, sanitizeFileName(fileName));
      partFile = File('${target.path}.part');
      final sink = partFile.openWrite();
      var written = 0;
      try {
        await for (final chunk in data) {
          sink.add(chunk);
          written += chunk.length;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      // El nombre pudo ocuparse mientras se subía: volver a resolver.
      final finalTarget = await uniqueFileIn(dir, p.basename(target.path));
      await partFile.rename(finalTarget.path);
      final finalName = p.basename(finalTarget.path);
      AppLogger.instance.info('[MobileServerStorage] saved file: $finalName ($written bytes)');
      return finalName;
    } catch (e) {
      AppLogger.instance.error('[MobileServerStorage] saveFile failed', error: e);
      try {
        if (partFile != null && await partFile.exists()) await partFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Elimina un archivo por nombre. Devuelve false si no existe o el nombre
  /// no es válido (rutas, `..`).
  Future<bool> deleteFile(String fileName) async {
    try {
      final file = resolveInside(await getDirectory(), fileName);
      if (file == null) {
        AppLogger.instance.warn('[MobileServerStorage] deleteFile: invalid name rejected');
        return false;
      }
      if (await file.exists()) {
        await file.delete();
        AppLogger.instance.info('[MobileServerStorage] deleted file: $fileName');
        return true;
      }
      AppLogger.instance.warn('[MobileServerStorage] deleteFile: file not found: $fileName');
      return false;
    } catch (e) {
      AppLogger.instance.error('[MobileServerStorage] deleteFile failed', error: e);
      rethrow;
    }
  }

  /// Retorna el archivo por nombre. Null si no existe o el nombre no es válido.
  Future<File?> getFile(String fileName) async {
    final file = resolveInside(await getDirectory(), fileName);
    if (file == null) return null;
    return await file.exists() ? file : null;
  }

  /// Calcula el espacio usado en el directorio y el espacio disponible del sistema.
  Future<DiskStats> getStats() async {
    final dir = await getDirectory();
    int used = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && !isHiddenFileName(p.basename(entity.path))) {
          used += (await entity.stat()).size;
        }
      }
    }

    int total = 0;
    int free = 0;
    try {
      final freeMb = await _diskChannel.invokeMethod<double>('getFreeDiskSpace');
      final totalMb = await _diskChannel.invokeMethod<double>('getTotalDiskSpace');
      free = ((freeMb ?? 0) * 1024 * 1024).round();
      total = ((totalMb ?? 0) * 1024 * 1024).round();
    } catch (e) {
      AppLogger.instance.warn('[MobileServerStorage] could not get disk space from platform channel: $e');
    }

    return DiskStats(total: total, used: used, free: free);
  }
}
