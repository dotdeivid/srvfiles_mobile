import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';

void main() {
  group('EmbeddedRelay', () {
    late EmbeddedRelay relay;

    setUp(() {
      relay = EmbeddedRelay();
    });

    tearDown(() async {
      await relay.stop();
    });

    test('starts and exposes health endpoint', () async {
      await relay.start(port: 0);
      expect(relay.isRunning, true);
      expect(relay.port, greaterThan(0));

      // Call health endpoint
      final response = await HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:${relay.port}/api/health'))
          .then((req) => req.close());
      expect(response.statusCode, 200);

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['status'], 'ok');
      expect(json['app'], 'srvfiles');
      expect(json['relay'], true);
    });

    test('returns 404 for unknown paths', () async {
      await relay.start(port: 0);

      final response = await HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:${relay.port}/api/unknown'))
          .then((req) => req.close());
      expect(response.statusCode, 404);
    });

    test('stop closes the server', () async {
      await relay.start(port: 0);
      expect(relay.isRunning, true);

      await relay.stop();
      expect(relay.isRunning, false);
    });

    test('WebSocket handshake hello → welcome + clients', () async {
      await relay.start(port: 0);

      final ws = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final messages = <Map<String, dynamic>>[];

      ws.listen((data) {
        if (data is String) {
          messages.add(jsonDecode(data) as Map<String, dynamic>);
        }
      });

      // Send hello
      ws.add(jsonEncode({
        'type': 'hello',
        'appName': 'TestDevice',
        'deviceType': 'mobile',
      }));

      // Wait for welcome + clients
      await Future.delayed(const Duration(milliseconds: 200));

      expect(messages.length, greaterThanOrEqualTo(2));
      // First message should be welcome
      final welcome = messages.firstWhere((m) => m['type'] == 'welcome');
      expect(welcome['clientId'], isNotEmpty);

      // Second should be clients broadcast
      final clients = messages.firstWhere((m) => m['type'] == 'clients');
      final clientList = clients['clients'] as List<dynamic>;
      expect(clientList.length, 1);
      expect((clientList[0] as Map)['appName'], 'TestDevice');
      expect((clientList[0] as Map)['deviceType'], 'mobile');

      await ws.close();
    });

    test('two clients see each other', () async {
      await relay.start(port: 0);

      final ws1 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');

      final messages1 = <Map<String, dynamic>>[];
      final messages2 = <Map<String, dynamic>>[];

      ws1.listen((data) {
        if (data is String) messages1.add(jsonDecode(data) as Map<String, dynamic>);
      });
      ws2.listen((data) {
        if (data is String) messages2.add(jsonDecode(data) as Map<String, dynamic>);
      });

      ws1.add(jsonEncode({'type': 'hello', 'appName': 'Client1'}));
      await Future.delayed(const Duration(milliseconds: 100));

      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Client2'}));
      await Future.delayed(const Duration(milliseconds: 200));

      // Both should have received a clients broadcast with 2 entries
      final lastClients1 = messages1.lastWhere((m) => m['type'] == 'clients');
      final list1 = lastClients1['clients'] as List<dynamic>;
      expect(list1.length, 2);

      final lastClients2 = messages2.lastWhere((m) => m['type'] == 'clients');
      final list2 = lastClients2['clients'] as List<dynamic>;
      expect(list2.length, 2);

      await ws1.close();
      await ws2.close();
    });

    test('disconnect broadcasts updated client list', () async {
      await relay.start(port: 0);

      final ws1 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');

      final messages1 = <Map<String, dynamic>>[];

      ws1.listen((data) {
        if (data is String) messages1.add(jsonDecode(data) as Map<String, dynamic>);
      });
      ws2.listen((data) {});

      ws1.add(jsonEncode({'type': 'hello', 'appName': 'Stays'}));
      await Future.delayed(const Duration(milliseconds: 100));
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Leaves'}));
      await Future.delayed(const Duration(milliseconds: 200));

      // Close ws2
      await ws2.close();
      await Future.delayed(const Duration(milliseconds: 200));

      // ws1 should get a clients broadcast with only 1 client
      final lastClients = messages1.lastWhere((m) => m['type'] == 'clients');
      final list = lastClients['clients'] as List<dynamic>;
      expect(list.length, 1);
      expect((list[0] as Map)['appName'], 'Stays');

      await ws1.close();
    });

    test('send-request relay between two clients', () async {
      await relay.start(port: 0);

      final ws1 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');

      final messages1 = <Map<String, dynamic>>[];
      final messages2 = <Map<String, dynamic>>[];

      ws1.listen((data) {
        if (data is String) messages1.add(jsonDecode(data) as Map<String, dynamic>);
      });
      ws2.listen((data) {
        if (data is String) messages2.add(jsonDecode(data) as Map<String, dynamic>);
      });

      ws1.add(jsonEncode({'type': 'hello', 'appName': 'Sender'}));
      await Future.delayed(const Duration(milliseconds: 100));
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Receiver'}));
      await Future.delayed(const Duration(milliseconds: 200));

      // Get client IDs
      final welcome1 = messages1.firstWhere((m) => m['type'] == 'welcome');
      final welcome2 = messages2.firstWhere((m) => m['type'] == 'welcome');
      final id2 = welcome2['clientId'] as String;

      // Send request from ws1 to ws2
      ws1.add(jsonEncode({
        'type': 'send-request',
        'to': id2,
        'fileName': 'test.txt',
        'fileSize': 100,
        'mimeType': 'text/plain',
        'transferId': 'transfer-001',
      }));
      await Future.delayed(const Duration(milliseconds: 200));

      // ws2 should receive the send-request
      final request = messages2.firstWhere(
        (m) => m['type'] == 'send-request',
        orElse: () => <String, dynamic>{},
      );
      expect(request['type'], 'send-request');
      expect(request['from'], welcome1['clientId']);
      expect(request['fromName'], 'Sender');
      expect(request['fileName'], 'test.txt');
      expect(request['transferId'], 'transfer-001');

      // ws2 accepts
      ws2.add(jsonEncode({
        'type': 'send-accept',
        'transferId': 'transfer-001',
      }));
      await Future.delayed(const Duration(milliseconds: 200));

      // ws1 should receive send-accept
      final accept = messages1.firstWhere(
        (m) => m['type'] == 'send-accept',
        orElse: () => <String, dynamic>{},
      );
      expect(accept['type'], 'send-accept');
      expect(accept['transferId'], 'transfer-001');

      await ws1.close();
      await ws2.close();
    });
  });
}
