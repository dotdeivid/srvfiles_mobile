import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/services/files_service.dart';

/// Servidor HTTP mínimo. [handler] recibe cada petición y responde.
Future<HttpServer> startServer(Future<void> Function(HttpRequest req) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

Future<void> json(HttpRequest req, int status, Object body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await req.response.close();
}

void main() {
  late HttpServer server;
  late FilesService service;

  tearDown(() async {
    service.close();
    await server.close(force: true);
  });

  FilesService serviceFor(HttpServer s) =>
      FilesService(ApiConfig('http://127.0.0.1:${s.port}'));

  test('getFiles sends the token and skips malformed entries', () async {
    String? token;
    server = await startServer((req) async {
      token = req.headers.value('X-SrvFiles-Token');
      await json(req, 200, {
        'files': [
          {'name': 'doc.pdf', 'size': 1024, 'createdAt': '2026-03-20T10:00:00Z', 'downloadUrl': '/x'},
          {'size': 5}, // sin nombre: se descarta
          'basura',
        ],
      });
    });
    service = serviceFor(server)..setToken('tok-1');

    final files = await service.getFiles();
    expect(token, 'tok-1');
    expect(files.map((f) => f.name), ['doc.pdf']);
  });

  test('maps 401 to AuthRequiredException and other errors to ServerException', () async {
    server = await startServer((req) async {
      await json(req, req.uri.path == '/api/files' ? 401 : 500, {'error': 'x'});
    });
    service = serviceFor(server);

    expect(service.getFiles(), throwsA(isA<AuthRequiredException>()));
    expect(service.getStats(), throwsA(isA<ServerException>()));
  });

  test('deleteFile reports success from the status code', () async {
    server = await startServer((req) async {
      await json(req, req.uri.path.endsWith('ok.txt') ? 200 : 404, {});
    });
    service = serviceFor(server);

    expect(await service.deleteFile('ok.txt'), true);
    expect(await service.deleteFile('missing.txt'), false);
  });

  test('uploadFiles streams the files, reports progress and partial failures', () async {
    var receivedBytes = 0;
    server = await startServer((req) async {
      await for (final chunk in req) {
        receivedBytes += chunk.length;
      }
      await json(req, 200, {
        'files': ['a.bin'],
        'failed': [{'name': 'b.bin', 'reason': 'No se pudo guardar'}],
      });
    });
    service = serviceFor(server);

    final dir = Directory.systemTemp.createTempSync('upload_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final a = File('${dir.path}/a.bin')..writeAsBytesSync(List.filled(200000, 1));
    final b = File('${dir.path}/b.bin')..writeAsBytesSync(List.filled(1000, 2));

    var lastProgress = 0.0;
    final failed = await service.uploadFiles([a, b], onProgress: (p) => lastProgress = p);

    expect(failed, ['b.bin']);
    expect(receivedBytes, greaterThan(201000));
    expect(lastProgress, closeTo(1.0, 0.001));
  });

  test('downloadTo writes the file and leaves nothing behind on error', () async {
    server = await startServer((req) async {
      if (req.uri.path.endsWith('ok.bin')) {
        req.response.add(List.filled(5000, 7));
        await req.response.close();
      } else {
        await json(req, 404, {});
      }
    });
    service = serviceFor(server);

    final dir = Directory.systemTemp.createTempSync('download_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final ok = File('${dir.path}/ok.bin');
    await service.downloadTo('ok.bin', ok);
    expect(ok.lengthSync(), 5000);

    final missing = File('${dir.path}/missing.bin');
    await expectLater(service.downloadTo('missing.bin', missing), throwsA(isA<ServerException>()));
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['ok.bin']);
  });
}
