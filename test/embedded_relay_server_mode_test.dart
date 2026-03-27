import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';

void main() {
  group('EmbeddedRelay server mode', () {
    late EmbeddedRelay relay;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      relay = EmbeddedRelay();
      await relay.start(port: 0);
    });

    tearDown(() async {
      await relay.stop();
    });

    Future<HttpClientResponse> getPath(String path) async {
      return HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:${relay.port}$path'))
          .then((req) => req.close());
    }

    Future<HttpClientResponse> postJson(
      String path,
      Map<String, dynamic> body,
    ) async {
      final req = await HttpClient()
          .postUrl(Uri.parse('http://127.0.0.1:${relay.port}$path'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      return req.close();
    }

    Future<String> bodyOf(HttpClientResponse r) =>
        r.transform(utf8.decoder).join();

    // ── startServerMode / stopServerMode ────────────────────────────────────

    test('startServerMode returns 6-digit PIN', () async {
      final pin = await relay.startServerMode();
      expect(pin.length, 6);
      expect(int.tryParse(pin), isNotNull);
      expect(relay.isServerMode, true);
      expect(relay.currentPin, pin);
    });

    test('stopServerMode clears pin and serverMode flag', () async {
      await relay.startServerMode();
      await relay.stopServerMode();
      expect(relay.isServerMode, false);
      expect(relay.currentPin, isNull);
    });

    // ── OPTIONS (CORS preflight) ─────────────────────────────────────────────

    test('OPTIONS request returns 200', () async {
      final req = await HttpClient().openUrl(
        'OPTIONS',
        Uri.parse('http://127.0.0.1:${relay.port}/api/files'),
      );
      final resp = await req.close();
      expect(resp.statusCode, 200);
    });

    // ── /api/auth ────────────────────────────────────────────────────────────

    test('/api/auth with wrong pin returns 401', () async {
      await relay.startServerMode();
      final resp = await postJson('/api/auth', {'pin': '000000'});
      expect(resp.statusCode, 401);
    });

    test('/api/auth with correct pin returns token', () async {
      final pin = await relay.startServerMode();
      final resp = await postJson('/api/auth', {'pin': pin});
      expect(resp.statusCode, 200);
      final body = jsonDecode(await bodyOf(resp)) as Map<String, dynamic>;
      expect(body['token'], isNotEmpty);
    });

    test('/api/auth with invalid JSON returns 400', () async {
      await relay.startServerMode();
      final req = await HttpClient()
          .postUrl(Uri.parse('http://127.0.0.1:${relay.port}/api/auth'));
      req.headers.contentType = ContentType.json;
      req.write('not-json');
      final resp = await req.close();
      expect(resp.statusCode, 400);
    });

    // ── Protected routes require token ──────────────────────────────────────

    test('/api/files returns 401 without token in server mode', () async {
      await relay.startServerMode();
      final resp = await getPath('/api/files');
      expect(resp.statusCode, 401);
    });

    test('/api/unknown returns 401 without token (unauthorized first)', () async {
      await relay.startServerMode();
      final resp = await getPath('/api/unknown');
      expect(resp.statusCode, 401);
    });

    // ── /api/health (always public) ──────────────────────────────────────────

    test('setDeviceName is reflected in /api/health', () async {
      relay.setDeviceName('Mi Teléfono');
      final resp = await getPath('/api/health');
      final body = jsonDecode(await bodyOf(resp)) as Map<String, dynamic>;
      expect(body['appName'], 'Mi Teléfono');
    });

    // ── url / port getters ────────────────────────────────────────────────────

    test('port getter returns positive value', () async {
      expect(relay.port, greaterThan(0));
    });

    test('isRunning is true after start', () {
      expect(relay.isRunning, true);
    });

    // ── stop ─────────────────────────────────────────────────────────────────

    test('stop sets isRunning to false', () async {
      await relay.stop();
      expect(relay.isRunning, false);
      // Re-start for tearDown
      await relay.start(port: 0);
    });
  });
}
