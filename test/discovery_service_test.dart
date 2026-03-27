import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/discovery_service.dart';

/// Starts a simple HTTP server that responds with [body] and [statusCode].
Future<HttpServer> startServer({
  required Map<String, dynamic> Function(String path) handler,
  int statusCode = 200,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = handler(req.uri.path);
    req.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  });
  return server;
}

void main() {
  group('DiscoveryService.probe', () {
    late DiscoveryService service;

    setUp(() {
      service = DiscoveryService();
    });

    test('returns DiscoveredServer for a valid SrvFiles endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'ok',
            'app': 'srvfiles',
            'appName': 'Mi Servidor',
          }));
        await req.response.close();
      });

      final url = 'http://127.0.0.1:${server.port}';
      final result = await service.probe(url);

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.appName, 'Mi Servidor');
      expect(result.ip, '127.0.0.1');

      await server.close(force: true);
    });

    test('returns null when app field is not srvfiles', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'ok', 'app': 'other-app'}));
        await req.response.close();
      });

      final result = await service.probe('http://127.0.0.1:${server.port}');
      expect(result, isNull);

      await server.close(force: true);
    });

    test('returns null when status field is not ok', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'error', 'app': 'srvfiles'}));
        await req.response.close();
      });

      final result = await service.probe('http://127.0.0.1:${server.port}');
      expect(result, isNull);

      await server.close(force: true);
    });

    test('returns null when HTTP status is non-200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 404
          ..write('Not Found');
        await req.response.close();
      });

      final result = await service.probe('http://127.0.0.1:${server.port}');
      expect(result, isNull);

      await server.close(force: true);
    });

    test('returns null for unreachable host (connection error)', () async {
      // Use a port that is not listening
      final result = await service.probe(
        'http://127.0.0.1:19999',
        timeout: const Duration(milliseconds: 300),
      );
      expect(result, isNull);
    });

    test('uses app field as appName when appName field is missing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'ok', 'app': 'srvfiles'}));
        await req.response.close();
      });

      final result = await service.probe('http://127.0.0.1:${server.port}');
      expect(result, isNotNull);
      expect(result!.appName, isNotEmpty);

      await server.close(force: true);
    });
  });

  group('DiscoveryService.tryConnect', () {
    late DiscoveryService service;

    setUp(() {
      service = DiscoveryService();
    });

    test('returns true for a valid SrvFiles server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'ok', 'app': 'srvfiles'}));
        await req.response.close();
      });

      final ok = await service.tryConnect('http://127.0.0.1:${server.port}');
      expect(ok, true);

      await server.close(force: true);
    });

    test('returns false when app is not srvfiles', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'ok', 'app': 'nextcloud'}));
        await req.response.close();
      });

      final ok = await service.tryConnect('http://127.0.0.1:${server.port}');
      expect(ok, false);

      await server.close(force: true);
    });

    test('returns false for non-200 HTTP status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 503
          ..write('unavailable');
        await req.response.close();
      });

      final ok = await service.tryConnect('http://127.0.0.1:${server.port}');
      expect(ok, false);

      await server.close(force: true);
    });

    test('returns false when connection fails', () async {
      final ok = await service.tryConnect('http://127.0.0.1:19998');
      expect(ok, false);
    });
  });

  group('DiscoveryService.scanNetwork', () {
    late DiscoveryService service;

    setUp(() {
      service = DiscoveryService();
    });

    test('returns list of DiscoveredServers on success', () async {
      final serverList = [
        {'ip': '192.168.1.10', 'url': 'http://192.168.1.10:3001', 'appName': 'PC Sala'},
        {'ip': '192.168.1.20', 'url': 'http://192.168.1.20:3001', 'appName': 'Laptop'},
      ];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(serverList));
        await req.response.close();
      });

      final results = await service.scanNetwork('http://127.0.0.1:${server.port}');
      expect(results.length, 2);
      expect(results[0].appName, 'PC Sala');
      expect(results[1].appName, 'Laptop');
      expect(results[0].ip, '192.168.1.10');

      await server.close(force: true);
    });

    test('returns empty list on non-200 response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 500
          ..write('error');
        await req.response.close();
      });

      final results = await service.scanNetwork('http://127.0.0.1:${server.port}');
      expect(results, isEmpty);

      await server.close(force: true);
    });

    test('returns empty list when server is unreachable', () async {
      final results = await service.scanNetwork('http://127.0.0.1:19997');
      expect(results, isEmpty);
    });

    test('returns empty list for empty array response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode([]));
        await req.response.close();
      });

      final results = await service.scanNetwork('http://127.0.0.1:${server.port}');
      expect(results, isEmpty);

      await server.close(force: true);
    });
  });

  group('DiscoveredServer.fromJson', () {
    test('constructs from valid JSON', () {
      final server = DiscoveredServer.fromJson({
        'ip': '10.0.0.1',
        'url': 'http://10.0.0.1:3001',
        'appName': 'NAS',
      });
      expect(server.ip, '10.0.0.1');
      expect(server.url, 'http://10.0.0.1:3001');
      expect(server.appName, 'NAS');
    });
  });
}
