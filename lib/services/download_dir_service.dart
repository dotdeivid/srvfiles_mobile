import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_logger.dart';

/// Centralised service that resolves the directories where the app stores
/// downloads and P2P received files, for the current platform.
///
/// En Android se intenta la carpeta pública `Download/SrvFiles`. En Android
/// 10 se necesita `requestLegacyExternalStorage` (declarado en el manifest) y
/// en Android ≤ 9 el permiso de escritura; si el directorio público no se puede
/// crear o escribir se usa el almacenamiento propio de la app, sin lanzar
/// excepción. En iOS se usa `Documents/SrvFiles`, visible en la app Archivos.
class DownloadDirService {
  const DownloadDirService();

  static const _publicDownloads = '/storage/emulated/0/Download';

  /// Returns the directory where downloaded files should be saved.
  Future<Directory> getDownloadsDir() => _resolve(const ['SrvFiles']);

  /// Returns the directory where P2P received files are saved.
  Future<Directory> getReceivedDir() => _resolve(const ['SrvFiles', 'received']);

  Future<Directory> _resolve(List<String> segments) async {
    if (Platform.isAndroid) {
      final public = Directory(p.joinAll([_publicDownloads, ...segments]));
      if (await _isWritable(public)) return public;
      AppLogger.instance.warn('[DownloadDir] public storage not writable, using app storage');
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.joinAll([base.path, ...segments]));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Crea [dir] si hace falta y comprueba que se puede escribir en él.
  static Future<bool> _isWritable(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.srvfiles_write_test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
