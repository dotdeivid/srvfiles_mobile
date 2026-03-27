import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/direct_transfer_pool.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';
import 'package:srvfiles_mobile/models/transfer_client.dart';

void main() {
  group('DirectTransferPool', () {
    late EmbeddedRelay relay;
    late DirectTransferPool pool;

    setUp(() async {
      relay = EmbeddedRelay();
      await relay.start(port: 0);
      pool = DirectTransferPool();
    });

    tearDown(() async {
      pool.disposeAll();
      await relay.stop();
    });

    Future<void> waitMs([int ms = 300]) =>
        Future.delayed(Duration(milliseconds: ms));

    test('getConnection returns null on timeout when no owner exists', () async {
      // Connect to the relay but don't register an owner — the pool should
      // timeout waiting for the targetClientId and return null.
      final conn = await pool.getConnection(
        'http://127.0.0.1:${relay.port}',
        'LonelyVisitor',
      );
      expect(conn, isNull);
    });

    test('getConnection connects to relay and returns DirectPeerConnection', () async {
      // The relay needs an owner registered so the pool can find the targetClientId.
      // Connect a "owner" WebSocket first.
      final owner = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final ownerMsgs = <Map<String, dynamic>>[];
      owner.listen((d) {
        if (d is String) ownerMsgs.add(jsonDecode(d) as Map<String, dynamic>);
      });
      owner.add(jsonEncode({'type': 'hello', 'appName': 'Owner', 'isOwner': true}));
      await waitMs(200);

      final url = 'http://127.0.0.1:${relay.port}';
      final conn = await pool.getConnection(url, 'Visitor');

      expect(conn, isNotNull);
      expect(conn!.service.isConnected, true);
      expect(conn.targetClientId, isNotEmpty);

      await owner.close();
    });

    test('getConnection reuses existing connection', () async {
      final owner = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final ownerMsgs = <Map<String, dynamic>>[];
      owner.listen((d) {
        if (d is String) ownerMsgs.add(jsonDecode(d) as Map<String, dynamic>);
      });
      owner.add(jsonEncode({'type': 'hello', 'appName': 'Owner2'}));
      await waitMs(200);

      final url = 'http://127.0.0.1:${relay.port}';
      final conn1 = await pool.getConnection(url, 'Visitor');
      final conn2 = await pool.getConnection(url, 'Visitor');

      expect(conn1, isNotNull);
      expect(conn2, isNotNull);
      // Same underlying service (reused)
      expect(identical(conn1!.service, conn2!.service), true);

      await owner.close();
    });

    test('disposeAll closes all pool connections', () async {
      final owner = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      owner.listen((_) {});
      owner.add(jsonEncode({'type': 'hello', 'appName': 'Owner3'}));
      await waitMs(200);

      final url = 'http://127.0.0.1:${relay.port}';
      final conn = await pool.getConnection(url, 'Visitor');
      expect(conn, isNotNull);

      pool.disposeAll();
      await waitMs(100);

      expect(conn!.service.isConnected, false);

      await owner.close();
    });

    test('touch does not throw when url not in pool', () {
      // Should be a no-op
      expect(() => pool.touch('http://127.0.0.1:3001'), returnsNormally);
    });

    test('event callbacks are delegated through pool', () async {
      bool sendRequestReceived = false;
      pool.onSendRequest = (_) => sendRequestReceived = true;

      final owner = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final ownerMsgs = <Map<String, dynamic>>[];
      owner.listen((d) {
        if (d is String) ownerMsgs.add(jsonDecode(d) as Map<String, dynamic>);
      });
      owner.add(jsonEncode({'type': 'hello', 'appName': 'Owner4'}));
      await waitMs(200);

      final url = 'http://127.0.0.1:${relay.port}';
      final conn = await pool.getConnection(url, 'Visitor4');
      expect(conn, isNotNull);

      // Get pool's clientId from welcome
      final visitorClientId = conn!.service.clientId!;

      // Owner sends a file request to visitor
      owner.add(jsonEncode({
        'type': 'send-request',
        'to': visitorClientId,
        'fileName': 'img.png',
        'fileSize': 1024,
        'mimeType': 'image/png',
        'transferId': 'ev-001',
      }));
      await waitMs(300);

      expect(sendRequestReceived, true);

      await owner.close();
    });
  });

  // ─── _findRelayOwner (tested via getConnection behavior) ───────────────────

  group('TransferClient.isOwner', () {
    test('isOwner defaults to false when not set', () {
      const client = TransferClient(
        clientId: 'c1',
        appName: 'Test',
        receiving: false,
        ip: '192.168.1.1',
      );
      expect(client.isOwner, false);
    });

    test('isOwner is true when set', () {
      const client = TransferClient(
        clientId: 'c1',
        appName: 'Owner',
        receiving: false,
        ip: '192.168.1.1',
        isOwner: true,
      );
      expect(client.isOwner, true);
    });
  });
}
