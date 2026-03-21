import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/received_files_service.dart';

void main() {
  group('ReceivedFilesService', () {
    late Directory tempDir;
    late ReceivedFilesService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('srvfiles_test_');
      service = ReceivedFilesService(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getDirectory returns the injected directory', () async {
      final dir = await service.getDirectory();
      expect(dir.path, tempDir.path);
    });

    test('listFiles returns empty list for empty directory', () async {
      final files = await service.listFiles();
      expect(files, isEmpty);
    });

    test('saveFile writes bytes to directory', () async {
      final path = await service.saveFile('test.txt', [72, 101, 108, 108, 111]);
      expect(File(path).existsSync(), true);
      expect(File(path).readAsBytesSync(), [72, 101, 108, 108, 111]);
      expect(path, contains('test.txt'));
    });

    test('saveFile adds numeric suffix for duplicates', () async {
      await service.saveFile('doc.pdf', [1, 2, 3]);
      final path2 = await service.saveFile('doc.pdf', [4, 5, 6]);
      expect(path2, contains('doc (1).pdf'));

      final path3 = await service.saveFile('doc.pdf', [7, 8, 9]);
      expect(path3, contains('doc (2).pdf'));
    });

    test('saveFile handles files without extension', () async {
      await service.saveFile('README', [1, 2]);
      final path2 = await service.saveFile('README', [3, 4]);
      expect(path2, contains('README (1)'));
    });

    test('listFiles returns saved files sorted by date descending', () async {
      await service.saveFile('first.txt', [1]);
      // Small delay to ensure different modification times
      await Future.delayed(const Duration(milliseconds: 50));
      await service.saveFile('second.txt', [2]);

      final files = await service.listFiles();
      expect(files.length, 2);
      // Most recent first
      expect(files[0].name, 'second.txt');
      expect(files[1].name, 'first.txt');
    });

    test('listFiles returns correct file info', () async {
      await service.saveFile('data.bin', [0, 1, 2, 3, 4]);

      final files = await service.listFiles();
      expect(files.length, 1);
      expect(files[0].name, 'data.bin');
      expect(files[0].size, 5);
      expect(files[0].createdAt, isNotEmpty);
      expect(files[0].downloadUrl, contains('data.bin'));
    });

    test('deleteFile removes file from directory', () async {
      await service.saveFile('to_delete.txt', [1, 2, 3]);
      var files = await service.listFiles();
      expect(files.length, 1);

      await service.deleteFile('to_delete.txt');
      files = await service.listFiles();
      expect(files, isEmpty);
    });

    test('deleteFile does nothing if file not found', () async {
      // Should not throw
      await service.deleteFile('nonexistent.txt');
    });

    test('listFiles ignores subdirectories', () async {
      await service.saveFile('file.txt', [1]);
      Directory('${tempDir.path}/subdir').createSync();

      final files = await service.listFiles();
      expect(files.length, 1);
      expect(files[0].name, 'file.txt');
    });
  });
}
