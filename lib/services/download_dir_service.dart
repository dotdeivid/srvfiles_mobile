import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Centralised service that resolves download / received / server-storage
/// directories for the current platform (Android vs iOS).
///
/// Eliminates the duplicate `_getDownloadDir()` that existed in both
/// `HomeScreen` and `ReceivedFilesService`.
class DownloadDirService {
  const DownloadDirService();

  /// Returns the directory where downloaded files should be saved.
  /// On Android this is `/storage/emulated/0/Download/SrvFiles`.
  /// On iOS it's `<Documents>/SrvFiles`.
  Future<Directory> getDownloadsDir() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = Directory('/storage/emulated/0/Download');
      if (!await baseDir.exists()) {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final srvDir = Directory('${baseDir.path}/SrvFiles');
    if (!await srvDir.exists()) {
      await srvDir.create(recursive: true);
    }
    return srvDir;
  }

  /// Returns the directory where P2P received files are saved.
  Future<Directory> getReceivedDir() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = Directory('/storage/emulated/0/Download');
      if (!await baseDir.exists()) {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${baseDir.path}/SrvFiles/Recibidos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
