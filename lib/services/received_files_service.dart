import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_info.dart';
import '../utils/file_names.dart';
import 'download_dir_service.dart';
import 'mobile_server_storage_service.dart' show listFilesIn;

/// Gestiona los archivos recibidos por P2P. Van a la carpeta compartida
/// `Download/SrvFiles` (ver [DownloadDirService]), la misma de las descargas y
/// del modo servidor; si no se puede escribir ahí, al almacenamiento propio.
class ReceivedFilesService {
  Directory? _dir;
  final DownloadDirService _dirs;

  /// Constructor opcional para inyectar directorio en tests.
  ReceivedFilesService([this._dir]) : _dirs = const DownloadDirService();

  /// Obtiene (y crea si no existe) el directorio de archivos recibidos.
  Future<Directory> getDirectory() async {
    if (_dir != null) {
      if (!await _dir!.exists()) await _dir!.create(recursive: true);
      return _dir!;
    }
    _dir = await _dirs.getReceivedDir();
    return _dir!;
  }

  /// Escanea el directorio y retorna la lista de archivos ordenados por fecha
  /// (más reciente primero). `downloadUrl` es la ruta local del archivo.
  Future<List<FileInfo>> listFiles() async {
    final dir = await getDirectory();
    return listFilesIn(dir, (file, _) => file.path);
  }

  /// Guarda bytes en el directorio de recibidos. Retorna el path completo.
  Future<String> saveFile(String fileName, List<int> bytes) async {
    final sink = await openWrite(fileName);
    sink.add(bytes);
    return sink.commit();
  }

  /// Abre un archivo temporal (`.part`) para escribir una recepción en
  /// streaming. El nombre que manda el otro dispositivo se sanea: solo se
  /// usa el último componente, sin rutas ni `..`.
  Future<ReceivedFileSink> openWrite(String fileName) async {
    final dir = await getDirectory();
    final safeName = sanitizeFileName(fileName);
    final target = await uniqueFileIn(dir, safeName);
    final part = File('${target.path}.part');
    return ReceivedFileSink._(dir, safeName, part, part.openWrite());
  }

  /// Elimina un archivo recibido por nombre. Ignora nombres con rutas.
  Future<void> deleteFile(String fileName) async {
    final file = resolveInside(await getDirectory(), fileName);
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }
}

/// Escritura en curso de un archivo recibido.
class ReceivedFileSink {
  final Directory _dir;
  final String _name;
  final File _part;
  final IOSink _sink;
  int bytesWritten = 0;
  bool _closed = false;

  ReceivedFileSink._(this._dir, this._name, this._part, this._sink);

  void add(List<int> data) {
    _sink.add(data);
    bytesWritten += data.length;
  }

  /// Cierra el archivo y lo renombra a su nombre final. Retorna la ruta.
  Future<String> commit() async {
    _closed = true;
    await _sink.flush();
    await _sink.close();
    final target = await uniqueFileIn(_dir, _name);
    await _part.rename(target.path);
    return target.path;
  }

  /// Descarta lo escrito (transferencia cancelada o incompleta).
  Future<void> discard() async {
    if (!_closed) {
      _closed = true;
      try {
        await _sink.close();
      } catch (_) {}
    }
    try {
      if (await _part.exists()) await _part.delete();
    } catch (_) {}
  }

  String get partName => p.basename(_part.path);
}
