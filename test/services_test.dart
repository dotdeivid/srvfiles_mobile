import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/services/device_name_service.dart';
import 'package:srvfiles_mobile/services/mobile_server_storage_service.dart';
import 'package:srvfiles_mobile/services/pin_service.dart';
import 'package:srvfiles_mobile/services/received_files_service.dart';

void main() {
  group('PinService', () {
    test('validates the generated PIN and nothing else', () {
      final service = PinService();
      expect(service.validatePin('123456'), false); // sin PIN activo
      final pin = service.generatePin();
      expect(pin, matches(RegExp(r'^[1-9]\d{5}$')));
      expect(service.validatePin(pin), true);
      expect(service.validatePin('000000'), false);
      expect(service.validatePin('$pin '), false);
    });

    test('clearPin invalidates the PIN', () {
      final service = PinService();
      final pin = service.generatePin();
      service.clearPin();
      expect(service.validatePin(pin), false);
    });
  });

  group('DeviceNameService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('first launch generates one name and keeps returning it', () async {
      final service = DeviceNameService();
      final first = await service.getName();
      expect(first, isNotEmpty);
      expect(await service.isFirstLaunch(), false); // ya quedó guardado
      expect(await service.getName(), first);
    });

    test('saveName persists; empty input falls back to a random name', () async {
      final service = DeviceNameService();
      expect(await service.saveName('Tablet Pro'), 'Tablet Pro');
      expect(await service.getName(), 'Tablet Pro');
      final random = await service.saveName('   ');
      expect(random, isNotEmpty);
      expect(await service.getName(), random);
    });
  });

  // Los dos almacenamientos comparten las reglas de nombres; se prueban juntos.
  group('storage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('storage_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('server storage: dedup, sanitizing and listing order', () async {
      final storage = MobileServerStorageService.forTesting(dir);
      expect(await storage.saveFile('doc.pdf', [1]), 'doc.pdf');
      expect(await storage.saveFile('doc.pdf', [2]), 'doc (1).pdf');
      expect(await storage.saveFile('../../etc/passwd', [3]), 'passwd');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await storage.saveFile('ultimo.txt', [4]);
      Directory('${dir.path}/subdir').createSync();
      File('${dir.path}/subiendo.bin.part').writeAsStringSync('x');

      final files = await storage.listFiles();
      expect(files.map((f) => f.name), containsAll(['doc.pdf', 'doc (1).pdf', 'passwd', 'ultimo.txt']));
      expect(files, hasLength(4)); // sin subdirectorios ni .part
      expect(files.first.name, 'ultimo.txt');
      expect(files.first.downloadUrl, '/api/files/download/ultimo.txt');
    });

    test('server storage: get/delete reject traversal and report missing files', () async {
      final storage = MobileServerStorageService.forTesting(dir);
      final outside = File('${dir.parent.path}/fuera_${dir.hashCode}.txt')..writeAsStringSync('x');
      addTearDown(() { if (outside.existsSync()) outside.deleteSync(); });

      expect(await storage.getFile('../${outside.uri.pathSegments.last}'), isNull);
      expect(await storage.deleteFile('../${outside.uri.pathSegments.last}'), false);
      expect(outside.existsSync(), true);
      expect(await storage.deleteFile('no-existe.txt'), false);

      await storage.saveFile('a.txt', [1]);
      expect(await storage.getFile('a.txt'), isNotNull);
      expect(await storage.deleteFile('a.txt'), true);
    });

    test('received files: streamed write commits or discards', () async {
      final service = ReceivedFilesService(dir);

      final sink = await service.openWrite('../foto.jpg');
      sink.add([1, 2]);
      sink.add([3]);
      final path = await sink.commit();
      expect(path, endsWith('foto.jpg'));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);

      final cancelled = await service.openWrite('foto.jpg');
      cancelled.add([9]);
      await cancelled.discard();

      final files = await service.listFiles();
      expect(files.map((f) => f.name), ['foto.jpg']);
    });
  });
}
