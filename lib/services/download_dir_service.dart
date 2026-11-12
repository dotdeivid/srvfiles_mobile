import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/file_names.dart';
import 'app_logger.dart';

/// Centralised service that resolves the directory where the app stores
/// downloads, P2P received files and the server-mode files: una sola carpeta
/// compartida, `Download/SrvFiles`, la misma que usan el servidor web y la app
/// de escritorio.
///
/// Sin permisos especiales: desde Android 11 la app ve en esa carpeta solo los
/// archivos que creó ella (lo que descargó, recibió o le subieron). Lo que se
/// copie a mano con otra app, o lo que quede de una instalación anterior, no
/// aparece en la lista.
///
/// En Android se intenta la carpeta pública `Download/SrvFiles`. En Android
/// 10 se necesita `requestLegacyExternalStorage` (declarado en el manifest) y
/// en Android ≤ 9 el permiso de escritura; si el directorio público no se puede
/// crear o escribir se usa el almacenamiento propio de la app, sin lanzar
/// excepción. En iOS se usa `Documents/SrvFiles`, visible en la app Archivos.
class DownloadDirService {
  const DownloadDirService();

  static const _publicDownloads = '/storage/emulated/0/Download';

  /// Carpeta compartida: descargas, archivos recibidos y modo servidor.
  Future<Directory> getDownloadsDir() async {
    final dir = await _resolve(const ['SrvFiles']);
    await _migrateLegacy(dir);
    return dir;
  }

  /// Los archivos recibidos van a la misma carpeta compartida.
  Future<Directory> getReceivedDir() => getDownloadsDir();

  static bool _migrated = false;

  /// Mueve una sola vez lo que quedó en las carpetas de versiones anteriores:
  /// `SrvFiles/received` (recibidos) y `Documents/SrvFiles/server` (modo
  /// servidor, que no se veía desde el gestor de archivos).
  Future<void> _migrateLegacy(Directory shared) async {
    if (_migrated) return;
    _migrated = true;
    final docs = await getApplicationDocumentsDirectory();
    for (final legacy in [
      Directory(p.join(shared.path, 'received')),
      Directory(p.join(docs.path, 'SrvFiles', 'server')),
    ]) {
      if (p.equals(legacy.path, shared.path)) continue;
      await moveFilesInto(legacy, shared);
    }
  }

  /// Mueve los archivos visibles de [from] a [to] sin sobrescribir (`a (1).txt`)
  /// y borra [from] si queda vacía. Público para tests.
  static Future<void> moveFilesInto(Directory from, Directory to) async {
    if (!await from.exists()) return;
    try {
      await for (final entity in from.list(followLinks: false)) {
        if (entity is! File || isHiddenFileName(p.basename(entity.path))) continue;
        final target = await uniqueFileIn(to, p.basename(entity.path));
        try {
          await entity.rename(target.path);
        } on FileSystemException {
          // Otro volumen: copiar y borrar.
          await entity.copy(target.path);
          await entity.delete();
        }
      }
      if (await from.list().isEmpty) await from.delete();
      AppLogger.instance.info('[DownloadDir] migrated ${from.path} → ${to.path}');
    } catch (e) {
      AppLogger.instance.warn('[DownloadDir] could not migrate ${from.path}: $e');
    }
  }

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
