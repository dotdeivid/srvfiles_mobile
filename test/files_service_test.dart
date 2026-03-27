import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/services/files_service.dart';

/// Starts a minimal HTTP server. [routes] maps path → (statusCode, body).
Future<HttpServer> startMockServer(
  Map<String, ({int status, dynamic body})> routes,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final route = routes[req.uri.path];
    if (route == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response
      ..statusCode = route.status
      ..headers.contentType = ContentType.json
      ..write(
        route.body is String ? route.body : jsonEncode(route.body),
      );
    await req.response.close();
  });
  return server;
}

void main() {
  group('FilesService', () {
    // ── token / authHeaders ───────────────────────────────────────────────────

    test('authHeaders is empty when no token set', () {
      final service = FilesService(ApiConfig('http://localhost:3001'));
      expect(service.authHeaders, isEmpty);
    });

    test('authHeaders contains token after setToken', () {
      final service = FilesService(ApiConfig('http://localhost:3001'));
      service.setToken('my-secret-token');
      expect(service.authHeaders['X-SrvFiles-Token'], 'my-secret-token');
    });

    // ── getFiles ──────────────────────────────────────────────────────────────

    test('getFiles returns parsed list on 200', () async {
      final server = await startMockServer({
        '/api/files': (
          status: 200,
          body: {
            'files': [
              {
                'name': 'doc.pdf',
                'size': 1024,
                'createdAt': '2026-03-20T10:00:00Z',
                'downloadUrl': '/api/files/download/doc.pdf',
              },
              {
                'name': 'photo.jpg',
                'size': 2048,
                'createdAt': '2026-03-21T09:00:00Z',
                'downloadUrl': '/api/files/download/photo.jpg',
              },
            ],
          },
        ),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final files = await service.getFiles();

      expect(files.length, 2);
      expect(files[0].name, 'doc.pdf');
      expect(files[0].size, 1024);
      expect(files[1].name, 'photo.jpg');

      await server.close(force: true);
    });

    test('getFiles throws on non-200 status', () async {
      final server = await startMockServer({
        '/api/files': (status: 401, body: 'Unauthorized'),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));

      expect(
        () => service.getFiles(),
        throwsA(isA<Exception>()),
      );

      await server.close(force: true);
    });

    // ── deleteFile ────────────────────────────────────────────────────────────

    test('deleteFile returns true on 200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.method == 'DELETE') {
          req.response.statusCode = 200;
        } else {
          req.response.statusCode = 405;
        }
        await req.response.close();
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final ok = await service.deleteFile('doc.pdf');
      expect(ok, true);

      await server.close(force: true);
    });

    test('deleteFile returns false on non-200 status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = 404;
        await req.response.close();
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final ok = await service.deleteFile('missing.pdf');
      expect(ok, false);

      await server.close(force: true);
    });

    // ── getStats ──────────────────────────────────────────────────────────────

    test('getStats parses DiskStats on 200', () async {
      final server = await startMockServer({
        '/api/files/stats': (
          status: 200,
          body: {'total': 1000000, 'used': 400000, 'free': 600000},
        ),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final stats = await service.getStats();

      expect(stats.total, 1000000);
      expect(stats.used, 400000);
      expect(stats.free, 600000);

      await server.close(force: true);
    });

    test('getStats throws on non-200', () async {
      final server = await startMockServer({
        '/api/files/stats': (status: 503, body: 'error'),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      expect(() => service.getStats(), throwsA(isA<Exception>()));

      await server.close(force: true);
    });

    // ── getConfig ─────────────────────────────────────────────────────────────

    test('getConfig parses AppConfig on 200', () async {
      final server = await startMockServer({
        '/api/config': (
          status: 200,
          body: {
            'appName': 'SrvFiles',
            'lanIp': '192.168.1.5',
            'port': 3001,
            'frontendPort': 5173,
            'maxFileSizeMb': 100,
            'lanUrl': 'http://192.168.1.5:3001',
          },
        ),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final cfg = await service.getConfig();

      expect(cfg.appName, 'SrvFiles');
      expect(cfg.lanIp, '192.168.1.5');
      expect(cfg.port, 3001);
      expect(cfg.maxFileSizeMb, 100);

      await server.close(force: true);
    });

    test('getConfig throws on non-200', () async {
      final server = await startMockServer({
        '/api/config': (status: 500, body: 'internal error'),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      expect(() => service.getConfig(), throwsA(isA<Exception>()));

      await server.close(force: true);
    });

    // ── healthCheck ───────────────────────────────────────────────────────────

    test('healthCheck returns true on 200', () async {
      final server = await startMockServer({
        '/api/health': (status: 200, body: {'status': 'ok'}),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final ok = await service.healthCheck();
      expect(ok, true);

      await server.close(force: true);
    });

    test('healthCheck returns false on non-200', () async {
      final server = await startMockServer({
        '/api/health': (status: 503, body: 'down'),
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      final ok = await service.healthCheck();
      expect(ok, false);

      await server.close(force: true);
    });

    test('healthCheck returns false when connection fails', () async {
      final service = FilesService(ApiConfig('http://127.0.0.1:19996'));
      final ok = await service.healthCheck();
      expect(ok, false);
    });

    // ── getDownloadUrl ────────────────────────────────────────────────────────

    test('getDownloadUrl returns correct URL with encoded filename', () {
      final service = FilesService(ApiConfig('http://192.168.1.10:3001'));
      final url = service.getDownloadUrl('my file.pdf');
      expect(url, 'http://192.168.1.10:3001/api/files/download/my%20file.pdf');
    });

    test('getDownloadUrl handles simple filename', () {
      final service = FilesService(ApiConfig('http://192.168.1.10:3001'));
      final url = service.getDownloadUrl('photo.jpg');
      expect(url, 'http://192.168.1.10:3001/api/files/download/photo.jpg');
    });

    // ── auth header forwarding ────────────────────────────────────────────────

    test('getFiles sends X-SrvFiles-Token header when token set', () async {
      String? receivedToken;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        receivedToken = req.headers.value('x-srvfiles-token');
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'files': []}));
        await req.response.close();
      });

      final service = FilesService(ApiConfig('http://127.0.0.1:${server.port}'));
      service.setToken('test-token-xyz');
      await service.getFiles();

      expect(receivedToken, 'test-token-xyz');

      await server.close(force: true);
    });
  });
}
