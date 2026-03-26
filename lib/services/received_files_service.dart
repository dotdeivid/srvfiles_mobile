import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/file_info.dart';

/// Gestiona el directorio local de archivos recibidos por P2P.
/// En Android: Download/SrvFiles/received/ (público, visible para galería/archivos).
/// En otros: Documents/SrvFiles/received/.
class ReceivedFilesService {
  Directory? _dir;

  /// Constructor opcional para inyectar directorio en tests.
  ReceivedFilesService([this._dir]);

  /// Obtiene (y crea si no existe) el directorio de archivos recibidos.
  Future<Directory> getDirectory() async {
    if (_dir != null) return _dir!;
    Directory baseDir;
    if (Platform.isAndroid) {
      final publicDownloads = Directory('/storage/emulated/0/Download');
      baseDir = await publicDownloads.exists()
          ? publicDownloads
          : await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${baseDir.path}/SrvFiles/received');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// Escanea el directorio y retorna la lista de archivos ordenados por fecha
  /// (más reciente primero).
  Future<List<FileInfo>> listFiles() async {
    final dir = await getDirectory();
    if (!await dir.exists()) return [];

    final entities = dir.listSync().whereType<File>().toList();

    // Ordenar por fecha de modificación descendente
    entities.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.modified.compareTo(aStat.modified);
    });

    return entities.map((file) {
      final stat = file.statSync();
      final name = file.path.split('/').last;
      return FileInfo(
        name: name,
        size: stat.size,
        createdAt: stat.modified.toIso8601String(),
        downloadUrl: file.path,
      );
    }).toList();
  }

  /// Guarda bytes en el directorio de recibidos. Retorna el path completo.
  Future<String> saveFile(String fileName, List<int> bytes) async {
    final dir = await getDirectory();
    final filePath = '${dir.path}/$fileName';

    // Si ya existe, agregar sufijo numérico
    var target = File(filePath);
    if (await target.exists()) {
      final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final base = ext.isNotEmpty
          ? fileName.substring(0, fileName.length - ext.length)
          : fileName;
      var i = 1;
      while (await target.exists()) {
        target = File('${dir.path}/$base ($i)$ext');
        i++;
      }
    }

    await target.writeAsBytes(bytes);
    return target.path;
  }

  /// Elimina un archivo recibido por nombre.
  Future<void> deleteFile(String fileName) async {
    final dir = await getDirectory();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
