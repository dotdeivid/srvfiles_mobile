import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';

/// Relay embebido: API HTTP del modo servidor, señalización WebSocket y las
/// reglas de seguridad que lo protegen. Clientes "crudos" (HttpClient y
/// WebSocket sin cifrar), como los usaría un navegador o un atacante.
void main() {
  late EmbeddedRelay relay;
  late HttpClient http;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    relay = EmbeddedRelay();
    await relay.start(port: 0);
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await relay.stop();
  });

  String base() => 'http://127.0.0.1:${relay.port}';

  Future<({int status, String body})> send(
    String method,
    String path, {
    String? token,
    Map<String, String> headers = const {},
    Object? json,
  }) async {
    final req = await http.openUrl(method, Uri.parse('${base()}$path'));
    if (token != null) req.headers.set('X-SrvFiles-Token', token);
    headers.forEach(req.headers.set);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    final res = await req.close();
    return (status: res.statusCode, body: await res.transform(utf8.decoder).join());
  }

  Future<String> login() async {
    final res = await send('POST', '/api/auth', json: {'pin': relay.currentPin});
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  }

  Future<int> upload(String token, String fileName, List<int> bytes) async {
    const boundary = 'srvfilestestboundary';
    final req = await http.postUrl(Uri.parse('${base()}/api/files/upload'));
    req.headers
      ..set('X-SrvFiles-Token', token)
      ..set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    req.add(utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="files"; filename="$fileName"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n'));
    req.add(bytes);
    req.add(utf8.encode('\r\n--$boundary--\r\n'));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  }

  test('health is public and reports relay state', () async {
    relay.setDeviceName('Mi Teléfono');
    final res = await send('GET', '/api/health');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(res.status, 200);
    expect(body['app'], 'srvfiles');
    expect(body['appName'], 'Mi Teléfono');
    expect(body['relay'], true);
    expect(body['serverMode'], false);
  });

  group('server mode', () {
    setUp(() => relay.startServerMode());

    test('PIN login: wrong → 401, bad JSON → 400, right → token', () async {
      expect((await send('POST', '/api/auth', json: {'pin': '000000'})).status, 401);
      final bad = await send('POST', '/api/auth', headers: {'content-type': 'application/json'});
      expect(bad.status, 400);
      expect(await login(), isNotEmpty);
    });

    test('/api/pin does not expose the PIN', () async {
      final res = await send('GET', '/api/pin');
      expect(res.status, isNot(200));
      expect(res.body.contains(relay.currentPin!), false);
    });

    test('rate limit returns 429 after 5 wrong PINs, even with the right one', () async {
      for (var i = 0; i < 5; i++) {
        expect((await send('POST', '/api/auth', json: {'pin': '000000'})).status, 401);
      }
      expect((await send('POST', '/api/auth', json: {'pin': relay.currentPin})).status, 429);
    });

    test('API requires a header token; query token only works for downloads', () async {
      expect((await send('GET', '/api/files')).status, 401);
      final token = await login();
      expect((await send('GET', '/api/files?token=$token')).status, 401);
      expect((await send('GET', '/api/files', token: token)).status, 200);
    });

    test('upload → list → download (with Range) → delete', () async {
      final token = await login();
      final data = List.generate(300000, (i) => i % 251);
      expect(await upload(token, 'año informe.bin', data), 200);

      final list = jsonDecode((await send('GET', '/api/files', token: token)).body)
          as Map<String, dynamic>;
      expect((list['files'] as List).single['name'], 'año informe.bin');

      final path = '/api/files/download/${Uri.encodeComponent('año informe.bin')}';
      final req = await http.getUrl(Uri.parse('${base()}$path?token=$token'));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
      final res = await req.close();
      final partial = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(res.statusCode, 206);
      expect(partial, data.sublist(10, 20));
      expect(res.headers.value('content-disposition'), contains("filename*=UTF-8''"));

      expect((await send('DELETE', '/api/files/${Uri.encodeComponent('año informe.bin')}', token: token)).status, 200);
      expect((await send('DELETE', '/api/files/no-existe.txt', token: token)).status, 404);
    });

    test('download and delete reject encoded path traversal', () async {
      final token = await login();
      expect((await send('GET', '/api/files/download/..%2F..%2Fsecret.txt', token: token)).status,
          anyOf(400, 404));
      expect((await send('DELETE', '/api/files/..%2Fshared_prefs.xml', token: token)).status,
          anyOf(400, 404));
    });

    test('tokens die when server mode is turned off', () async {
      final token = await login();
      await relay.stopServerMode();
      await relay.startServerMode();
      expect((await send('GET', '/api/files', token: token)).status, 401);
    });

    test('WebSocket without a valid token is closed with 4401', () async {
      // El relay lo cierra.
      // ignore: close_sinks
      final ws = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      ws.add(jsonEncode({'type': 'auth', 'token': 'inventado'}));
      await ws.drain<void>().timeout(const Duration(seconds: 3));
      expect(ws.closeCode, 4401);
    });
  });

  group('WebSocket signaling', () {
    Future<({WebSocket ws, List<Map<String, dynamic>> msgs, List<List<int>> bin, String id})> join(
      String name,
    ) async {
      // Lo cierra cada test.
      // ignore: close_sinks
      final ws = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final msgs = <Map<String, dynamic>>[];
      final bin = <List<int>>[];
      final welcome = Completer<String>();
      ws.listen((data) {
        if (data is String) {
          final m = jsonDecode(data) as Map<String, dynamic>;
          msgs.add(m);
          if (m['type'] == 'welcome' && !welcome.isCompleted) {
            welcome.complete(m['clientId'] as String);
          }
        } else if (data is List<int>) {
          bin.add(data);
        }
      });
      ws.add(jsonEncode({'type': 'hello', 'appName': name}));
      final id = await welcome.future.timeout(const Duration(seconds: 3));
      return (ws: ws, msgs: msgs, bin: bin, id: id);
    }

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 150));

    Uint8List frame(String transferId) =>
        Uint8List.fromList([...utf8.encode(transferId.padRight(36)), 1, 2, 3]);

    String request(String to, String id) => jsonEncode({
          'type': 'send-request', 'to': to, 'fileName': 'a.bin', 'fileSize': 3,
          'mimeType': 'application/octet-stream', 'transferId': id,
        });

    test('client list is broadcast on join and leave', () async {
      final a = await join('A');
      final b = await join('B');
      await settle();
      List names(List<Map<String, dynamic>> msgs) =>
          (msgs.lastWhere((m) => m['type'] == 'clients')['clients'] as List)
              .map((c) => c['appName'])
              .toList();
      expect(names(a.msgs), containsAll(['A', 'B']));

      await b.ws.close();
      await settle();
      expect(names(a.msgs), ['A']);
      await a.ws.close();
    });

    test('chunks flow only from the sender, only after accept', () async {
      final sender = await join('Sender');
      final receiver = await join('Receiver');
      final intruder = await join('Intruder');
      const id = 'tx-1';

      sender.ws.add(request(receiver.id, id));
      await settle();
      expect(receiver.msgs.where((m) => m['type'] == 'send-request'), hasLength(1));

      sender.ws.add(frame(id)); // todavía no aceptó
      await settle();
      expect(receiver.bin, isEmpty);

      receiver.ws.add(jsonEncode({'type': 'send-accept', 'transferId': id}));
      await settle();
      expect(sender.msgs.where((m) => m['type'] == 'send-accept'), hasLength(1));

      intruder.ws.add(frame(id));
      sender.ws.add(frame(id));
      await settle();
      expect(receiver.bin, hasLength(1));

      for (final c in [sender, receiver, intruder]) {
        await c.ws.close();
      }
    });

    test('duplicate transferId and offline targets are rejected', () async {
      final sender = await join('Sender');
      final receiver = await join('Receiver');
      sender.ws.add(request(receiver.id, 'tx-dup'));
      sender.ws.add(request(receiver.id, 'tx-dup'));
      sender.ws.add(request('no-existe', 'tx-off'));
      await settle();
      final rejects = sender.msgs.where((m) => m['type'] == 'send-reject').map((m) => m['reason']);
      expect(rejects, containsAll(['duplicate', 'offline']));
      await sender.ws.close();
      await receiver.ws.close();
    });

    test('a peer disconnecting mid-transfer cancels it for the other side', () async {
      final sender = await join('Sender');
      final receiver = await join('Receiver');
      sender.ws.add(request(receiver.id, 'tx-drop'));
      await settle();
      receiver.ws.add(jsonEncode({'type': 'send-accept', 'transferId': 'tx-drop'}));
      await settle();
      await sender.ws.close();
      await settle();
      expect(receiver.msgs.where((m) => m['type'] == 'send-cancel'), hasLength(1));
      await receiver.ws.close();
    });
  });
}
