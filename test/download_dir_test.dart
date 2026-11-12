import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/download_dir_service.dart';
import 'package:srvfiles_mobile/services/mobile_server_storage_service.dart';

/// Carpeta compartida Download/SrvFiles: migración desde las carpetas viejas
/// y listado sin archivos ocultos.
void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('download_dir_test_'));
  tearDown(() => tmp.delete(recursive: true));

  test('legacy folders are moved into the shared folder without overwriting', () async {
    final shared = Directory('${tmp.path}/SrvFiles')..createSync();
    final legacy = Directory('${shared.path}/received')..createSync();
    File('${shared.path}/a.txt').writeAsStringSync('ya estaba');
    File('${legacy.path}/a.txt').writeAsStringSync('recibido');
    File('${legacy.path}/.nomedia').writeAsStringSync('');

    await DownloadDirService.moveFilesInto(legacy, shared);

    expect(File('${shared.path}/a.txt').readAsStringSync(), 'ya estaba');
    expect(File('${shared.path}/a (1).txt').readAsStringSync(), 'recibido');
    // Los ocultos no se mueven, así que la carpeta vieja queda.
    expect(File('${legacy.path}/.nomedia').existsSync(), true);
  });

  test('the legacy folder is removed once empty', () async {
    final shared = Directory('${tmp.path}/SrvFiles')..createSync();
    final legacy = Directory('${tmp.path}/server')..createSync();
    File('${legacy.path}/b.pdf').writeAsStringSync('pdf');

    await DownloadDirService.moveFilesInto(legacy, shared);

    expect(File('${shared.path}/b.pdf').existsSync(), true);
    expect(legacy.existsSync(), false);
  });

  test('server listing hides system files and in-progress uploads', () async {
    for (final name in ['visible.txt', '.nomedia', 'subiendo.zip.part', 'desktop.ini']) {
      File('${tmp.path}/$name').writeAsStringSync('x');
    }
    final files = await MobileServerStorageService.forTesting(tmp).listFiles();
    expect(files.map((f) => f.name), ['visible.txt']);
  });
}
