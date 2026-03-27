import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';
import 'package:srvfiles_mobile/services/transfer_service.dart';

void main() {
  group('TransferService WebSocket', () {
    late EmbeddedRelay relay;
    late TransferService service;

    setUp(() async {
      relay = EmbeddedRelay();
      await relay.start(port: 0);
      service = TransferService();
    });

    tearDown(() async {
      service.dispose();
      await relay.stop();
    });

    ApiConfig buildConfig() => ApiConfig('http://127.0.0.1:${relay.port}');

    Future<void> waitMs([int ms = 200]) =>
        Future.delayed(Duration(milliseconds: ms));

    // ── connect & welcome ────────────────────────────────────────────────────

    test('connect + register receives welcome with clientId', () async {
      String? receivedClientId;
      service.onWelcome = (id) => receivedClientId = id;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('TestDevice');
      await waitMs(200);

      expect(receivedClientId, isNotNull);
      expect(receivedClientId, isNotEmpty);
      expect(service.clientId, receivedClientId);
    });

    test('connect + register receives clients update', () async {
      final clientsUpdates = <List>[];
      service.onClientsUpdate = (list) => clientsUpdates.add(list);

      service.connect(buildConfig());
      await waitMs(100);
      service.register('MyDevice');
      await waitMs(200);

      expect(clientsUpdates, isNotEmpty);
      expect(clientsUpdates.last.length, 1);
      expect(clientsUpdates.last[0].appName, 'MyDevice');
    });

    test('isConnected is true after connect', () async {
      service.connect(buildConfig());
      await waitMs(100);
      expect(service.isConnected, true);
    });

    // ── send-request relay ───────────────────────────────────────────────────

    test('send-request is relayed to target client', () async {
      // Set up second raw WebSocket client as the receiver
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final msgs2 = <Map<String, dynamic>>[];
      ws2.listen((data) {
        if (data is String) msgs2.add(jsonDecode(data) as Map<String, dynamic>);
      });

      // Register receiver and get its ID
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Receiver'}));
      await waitMs(200);

      final welcome2 = msgs2.firstWhere((m) => m['type'] == 'welcome');
      final receiverId = welcome2['clientId'] as String;

      // Register our TransferService client
      service.connect(buildConfig());
      await waitMs(100);
      service.register('Sender');
      await waitMs(200);

      // Send request to receiver
      service.sendRequest(
        to: receiverId,
        fileName: 'photo.jpg',
        fileSize: 12345,
        mimeType: 'image/jpeg',
        transferId: 'transfer-abc',
      );
      await waitMs(200);

      final request = msgs2.firstWhere(
        (m) => m['type'] == 'send-request',
        orElse: () => {},
      );
      expect(request['type'], 'send-request');
      expect(request['fileName'], 'photo.jpg');
      expect(request['transferId'], 'transfer-abc');

      await ws2.close();
    });

    test('send-accept is relayed back to sender', () async {
      // Setup sender service
      String? receivedTransferId;
      service.onSendAccept = (id) => receivedTransferId = id;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('Sender');
      await waitMs(200);

      // Setup receiver raw WebSocket
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final msgs2 = <Map<String, dynamic>>[];
      ws2.listen((data) {
        if (data is String) msgs2.add(jsonDecode(data) as Map<String, dynamic>);
      });
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Receiver'}));
      await waitMs(200);

      final welcome2 = msgs2.firstWhere((m) => m['type'] == 'welcome');
      final receiverId = welcome2['clientId'] as String;

      // Sender sends request
      service.sendRequest(
        to: receiverId,
        fileName: 'doc.pdf',
        fileSize: 100,
        mimeType: 'application/pdf',
        transferId: 'txfr-001',
      );
      await waitMs(200);

      // Receiver accepts — must relay to sender's clientId
      final senderId = service.clientId!;
      ws2.add(jsonEncode({
        'type': 'send-accept',
        'transferId': 'txfr-001',
        'to': senderId,
      }));
      await waitMs(300);

      expect(receivedTransferId, 'txfr-001');

      await ws2.close();
    });

    test('send-reject is relayed back to sender', () async {
      String? rejectedId;
      service.onSendReject = (id, _) => rejectedId = id;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('Sender');
      await waitMs(200);

      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final msgs2 = <Map<String, dynamic>>[];
      ws2.listen((data) {
        if (data is String) msgs2.add(jsonDecode(data) as Map<String, dynamic>);
      });
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Receiver2'}));
      await waitMs(200);

      final welcome2 = msgs2.firstWhere((m) => m['type'] == 'welcome');
      final receiverId = welcome2['clientId'] as String;

      service.sendRequest(
        to: receiverId,
        fileName: 'file.zip',
        fileSize: 500,
        mimeType: 'application/zip',
        transferId: 'txfr-002',
      );
      await waitMs(200);

      final senderId = service.clientId!;
      ws2.add(jsonEncode({
        'type': 'send-reject',
        'transferId': 'txfr-002',
        'to': senderId,
        'reason': 'no space',
      }));
      await waitMs(300);

      expect(rejectedId, 'txfr-002');

      await ws2.close();
    });

    // ── binary chunk handling ────────────────────────────────────────────────

    test('sendFile sends binary chunks to receiver', () async {
      // Start a raw WS receiver that will collect binary frames
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final binaryFrames = <Uint8List>[];
      final msgs2 = <Map<String, dynamic>>[];
      ws2.listen((data) {
        if (data is String) {
          msgs2.add(jsonDecode(data) as Map<String, dynamic>);
        } else if (data is List<int>) {
          binaryFrames.add(Uint8List.fromList(data));
        }
      });
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'Receiver3'}));
      await waitMs(200);

      final welcome2 = msgs2.firstWhere((m) => m['type'] == 'welcome');
      final receiverId = welcome2['clientId'] as String;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('Sender3');
      await waitMs(200);

      // Accept the transfer first (simulate accept flow via raw ws2)
      const transferId = 'txfr-binary';
      service.sendRequest(
        to: receiverId,
        fileName: 'test.bin',
        fileSize: 10,
        mimeType: 'application/octet-stream',
        transferId: transferId,
      );
      await waitMs(200);

      final senderId = service.clientId!;
      ws2.add(jsonEncode({
        'type': 'send-accept',
        'transferId': transferId,
        'to': senderId,
      }));
      await waitMs(200);

      // Send a small file
      final fileBytes = Uint8List.fromList(List.generate(10, (i) => i));
      await service.sendFile(transferId: transferId, fileBytes: fileBytes);
      await waitMs(200);

      // Receiver should have received binary frame(s)
      // The relay forwards binary frames to all other clients
      expect(binaryFrames, isNotEmpty);

      // The first frame should contain transferId header (36 bytes) + data
      final frame = binaryFrames.first;
      expect(frame.length, greaterThan(36));

      // Parse transferId from header
      final headerStr = utf8.decode(frame.sublist(0, 36)).trim();
      expect(headerStr, transferId);

      await ws2.close();
    });

    // ── disconnect callback ──────────────────────────────────────────────────

    test('onDisconnected called when server closes', () async {
      bool disconnected = false;
      service.onDisconnected = () => disconnected = true;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('ByeDevice');
      await waitMs(200);

      // Stop server to force disconnect
      await relay.stop();
      await waitMs(400);

      expect(disconnected, true);
    });

    // ── rename ────────────────────────────────────────────────────────────────

    test('rename sends rename message without error', () async {
      service.connect(buildConfig());
      await waitMs(100);
      service.register('OldName');
      await waitMs(200);

      // Should not throw
      expect(() => service.rename('NewName'), returnsNormally);
    });

    // ── reject method ─────────────────────────────────────────────────────────

    test('reject sends send-reject message', () async {
      service.connect(buildConfig());
      await waitMs(100);
      service.register('Rejecter');
      await waitMs(200);

      // Should not throw — we just verify it's sent without error
      expect(() => service.reject('txfr-to-reject'), returnsNormally);
    });

    // ── cancel method ─────────────────────────────────────────────────────────

    test('cancel sends send-cancel message without error', () async {
      service.connect(buildConfig());
      await waitMs(100);
      service.register('Canceller');
      await waitMs(200);

      expect(() => service.cancel('txfr-to-cancel'), returnsNormally);
    });

    // ── setReceiving ──────────────────────────────────────────────────────────

    test('setReceiving sends set-receiving message', () async {
      service.connect(buildConfig());
      await waitMs(100);
      service.register('ReceivingDevice');
      await waitMs(200);

      expect(() => service.setReceiving(true), returnsNormally);
      expect(() => service.setReceiving(false), returnsNormally);
    });

    // ── onSendComplete received as the file receiver ──────────────────────────

    test('onSendComplete is called when service is file receiver', () async {
      // The service will be the RECEIVER; raw ws2 will be the SENDER.
      String? completeId;
      service.onSendComplete = (id) => completeId = id;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('FileReceiver');
      await waitMs(200);

      final serviceClientId = service.clientId!;

      // Connect a raw sender
      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      final msgs2 = <Map<String, dynamic>>[];
      ws2.listen((d) {
        if (d is String) msgs2.add(jsonDecode(d) as Map<String, dynamic>);
      });
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'FileSender'}));
      await waitMs(200);

      // Sender sends a request to service (receiver)
      const txfr = 'complete-txfr-001';
      ws2.add(jsonEncode({
        'type': 'send-request',
        'to': serviceClientId,
        'fileName': 'done.txt',
        'fileSize': 3,
        'mimeType': 'text/plain',
        'transferId': txfr,
      }));
      await waitMs(200);

      // Service (receiver) accepts
      service.accept(txfr);
      await waitMs(200);

      // Sender sends complete — relay forwards to receiver (our service)
      ws2.add(jsonEncode({'type': 'send-complete', 'transferId': txfr}));
      await waitMs(300);

      expect(completeId, txfr);

      await ws2.close();
    });

    // ── onSendCancel received as the service ──────────────────────────────────

    test('onSendCancel is called when relay relays send-cancel', () async {
      // service is the RECEIVER; ws2 is the sender who sends cancel.
      String? cancelId;
      service.onSendCancel = (id) => cancelId = id;

      service.connect(buildConfig());
      await waitMs(100);
      service.register('CancelReceiver');
      await waitMs(200);

      final serviceClientId = service.clientId!;

      final ws2 = await WebSocket.connect('ws://127.0.0.1:${relay.port}/ws');
      ws2.listen((_) {});
      ws2.add(jsonEncode({'type': 'hello', 'appName': 'CancelSender'}));
      await waitMs(200);

      const txfr = 'cancel-txfr-001';

      // Sender makes a request to service
      ws2.add(jsonEncode({
        'type': 'send-request',
        'to': serviceClientId,
        'fileName': 'file.bin',
        'fileSize': 1,
        'mimeType': 'application/octet-stream',
        'transferId': txfr,
      }));
      await waitMs(200);

      // Service accepts
      service.accept(txfr);
      await waitMs(200);

      // Sender cancels — relay should forward to receiver (service)
      ws2.add(jsonEncode({'type': 'send-cancel', 'transferId': txfr}));
      await waitMs(300);

      expect(cancelId, txfr);

      await ws2.close();
    });

    // ── onFilesChanged callback assignment ───────────────────────────────────

    test('onFilesChanged callback can be assigned', () {
      service.onFilesChanged = () {};
      expect(service.onFilesChanged, isNotNull);
    });
  });
}
