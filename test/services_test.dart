import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/services/pin_service.dart';
import 'package:srvfiles_mobile/services/device_name_service.dart';
import 'package:srvfiles_mobile/services/mobile_server_storage_service.dart';
import 'package:srvfiles_mobile/services/transfer_service.dart';

void main() {
  // ─── PinService ──────────────────────────────────────────────────────────────

  group('PinService', () {
    late PinService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = PinService();
    });

    test('generatePin returns 6-digit string', () async {
      final pin = await service.generatePin();
      expect(pin.length, 6);
      expect(int.tryParse(pin), isNotNull);
      final value = int.parse(pin);
      expect(value, greaterThanOrEqualTo(100000));
      expect(value, lessThanOrEqualTo(999999));
    });

    test('generatePin saves hash so validatePin returns true', () async {
      final pin = await service.generatePin();
      final valid = await service.validatePin(pin);
      expect(valid, true);
    });

    test('validatePin returns false for wrong PIN', () async {
      await service.generatePin();
      final valid = await service.validatePin('000000');
      expect(valid, false);
    });

    test('validatePin returns false when no PIN has been generated', () async {
      final valid = await service.validatePin('123456');
      expect(valid, false);
    });

    test('clearPin causes validatePin to return false', () async {
      final pin = await service.generatePin();
      await service.clearPin();
      final valid = await service.validatePin(pin);
      expect(valid, false);
    });

    test('generatePin produces different PINs on repeated calls', () async {
      final pins = <String>{};
      for (var i = 0; i < 10; i++) {
        pins.add(await service.generatePin());
      }
      // With 10 calls there should be at least 2 distinct values statistically.
      // This is a probabilistic test — the chance of 10 identical 6-digit PINs is negligible.
      expect(pins.length, greaterThan(1));
    });
  });

  // ─── DeviceNameService ───────────────────────────────────────────────────────

  group('DeviceNameService', () {
    late DeviceNameService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = DeviceNameService();
    });

    test('getName returns saved name when one exists', () async {
      SharedPreferences.setMockInitialValues({'srvfiles-device-name': 'Mi Celular'});
      final name = await service.getName();
      expect(name, 'Mi Celular');
    });

    test('getName returns a non-empty random name when nothing saved', () async {
      final name = await service.getName();
      expect(name, isNotEmpty);
    });

    test('saveName saves provided name and returns it', () async {
      final saved = await service.saveName('Tablet Pro');
      expect(saved, 'Tablet Pro');

      // Verify it persists
      final retrieved = await service.getName();
      expect(retrieved, 'Tablet Pro');
    });

    test('saveName with empty string generates and saves a random name', () async {
      final saved = await service.saveName('   ');
      expect(saved, isNotEmpty);

      // Should now be persisted
      final retrieved = await service.getName();
      expect(retrieved, saved);
    });

    test('isFirstLaunch returns true when no name saved', () async {
      final first = await service.isFirstLaunch();
      expect(first, true);
    });

    test('isFirstLaunch returns false after saving a name', () async {
      await service.saveName('Test');
      final first = await service.isFirstLaunch();
      expect(first, false);
    });

    test('generateRandomName returns non-empty string with a space', () {
      final name = service.generateRandomName();
      expect(name, isNotEmpty);
      expect(name.contains(' '), true,
          reason: 'Name should be "Adjective Animal" with a space');
    });

    test('generateRandomName returns different values across calls', () {
      final names = <String>{};
      for (var i = 0; i < 20; i++) {
        names.add(service.generateRandomName());
      }
      expect(names.length, greaterThan(1));
    });
  });

  // ─── MobileServerStorageService ─────────────────────────────────────────────

  group('MobileServerStorageService', () {
    late Directory tempDir;
    late MobileServerStorageService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('srvfiles_server_test_');
      service = MobileServerStorageService.forTesting(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getDirectory returns injected directory', () async {
      final dir = await service.getDirectory();
      expect(dir.path, tempDir.path);
    });

    test('listFiles returns empty list for empty directory', () async {
      final files = await service.listFiles();
      expect(files, isEmpty);
    });

    test('saveFile writes bytes and returns final filename', () async {
      final name = await service.saveFile('hello.txt', [72, 101, 108, 108, 111]);
      expect(name, 'hello.txt');
      final file = File('${tempDir.path}/hello.txt');
      expect(file.existsSync(), true);
      expect(file.readAsBytesSync(), [72, 101, 108, 108, 111]);
    });

    test('saveFile deduplicates with numeric suffix', () async {
      await service.saveFile('doc.pdf', [1, 2, 3]);
      final name2 = await service.saveFile('doc.pdf', [4, 5, 6]);
      expect(name2, 'doc (1).pdf');

      final name3 = await service.saveFile('doc.pdf', [7, 8, 9]);
      expect(name3, 'doc (2).pdf');
    });

    test('saveFile handles files without extension', () async {
      await service.saveFile('README', [1]);
      final name2 = await service.saveFile('README', [2]);
      expect(name2, 'README (1)');
    });

    test('listFiles returns saved files sorted newest first', () async {
      await service.saveFile('first.txt', [1]);
      await Future.delayed(const Duration(milliseconds: 50));
      await service.saveFile('second.txt', [2]);

      final files = await service.listFiles();
      expect(files.length, 2);
      expect(files[0].name, 'second.txt');
      expect(files[1].name, 'first.txt');
    });

    test('listFiles returns correct FileInfo fields', () async {
      await service.saveFile('data.bin', [0, 1, 2, 3, 4]);

      final files = await service.listFiles();
      expect(files.length, 1);
      expect(files[0].name, 'data.bin');
      expect(files[0].size, 5);
      expect(files[0].createdAt, isNotEmpty);
      expect(files[0].downloadUrl, contains('data.bin'));
    });

    test('listFiles ignores subdirectories', () async {
      await service.saveFile('file.txt', [1]);
      Directory('${tempDir.path}/subdir').createSync();

      final files = await service.listFiles();
      expect(files.length, 1);
      expect(files[0].name, 'file.txt');
    });

    test('deleteFile removes the file', () async {
      await service.saveFile('to_delete.txt', [1, 2, 3]);
      expect((await service.listFiles()).length, 1);

      await service.deleteFile('to_delete.txt');
      expect((await service.listFiles()).length, 0);
    });

    test('deleteFile does nothing when file does not exist', () async {
      // Should not throw
      await service.deleteFile('nonexistent.txt');
    });

    test('getFile returns File when it exists', () async {
      await service.saveFile('present.txt', [10, 20]);
      final file = await service.getFile('present.txt');
      expect(file, isNotNull);
      expect(file!.existsSync(), true);
    });

    test('getFile returns null when file does not exist', () async {
      final file = await service.getFile('missing.txt');
      expect(file, isNull);
    });

    test('saveFile sanitizes path traversal characters', () async {
      final name = await service.saveFile('../../../etc/passwd', [1]);
      // Should not contain path traversal sequences
      expect(name.contains('/'), false);
      expect(name.contains('\\'), false);
      expect(name.contains('..'), false);
    });

    test('saveFile sanitizes dangerous characters', () async {
      final name = await service.saveFile('file:name?.txt', [1]);
      expect(name.contains(':'), false);
      expect(name.contains('?'), false);
    });

    test('saveFile uses fallback name for empty/invalid filename', () async {
      final name = await service.saveFile('...', [1]);
      // _sanitize replaces ".." with "_", resulting in non-empty name
      expect(name, isNotEmpty);
    });
  });

  // ─── TransferService (non-WebSocket) ─────────────────────────────────────────

  group('TransferService token management', () {
    late TransferService service;

    setUp(() {
      service = TransferService();
    });

    tearDown(() {
      service.dispose();
    });

    test('hasToken is false initially', () {
      expect(service.hasToken, false);
    });

    test('setToken makes hasToken true', () {
      service.setToken('abc123');
      expect(service.hasToken, true);
    });

    test('clearToken makes hasToken false', () {
      service.setToken('abc123');
      service.clearToken();
      expect(service.hasToken, false);
    });

    test('isConnected is false when not connected', () {
      expect(service.isConnected, false);
    });

    test('clientId is null before connecting', () {
      expect(service.clientId, isNull);
    });

    test('dispose sets isConnected to false', () {
      service.dispose();
      expect(service.isConnected, false);
    });
  });
}
