import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/features/transfer/transfer_controller.dart';
import 'package:srvfiles_mobile/services/device_name_service.dart';
import 'package:srvfiles_mobile/services/direct_transfer_pool.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';
import 'package:srvfiles_mobile/services/notification_service.dart';
import 'package:srvfiles_mobile/services/received_files_service.dart';
import 'package:srvfiles_mobile/services/transfer_service.dart';

/// Transferencias P2P de punta a punta a través del relay embebido, con
/// cifrado activo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmbeddedRelay relay;
  late Directory tmp;
  final services = <TransferService>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({'srvfiles-device-name': 'Receptor'});
    relay = EmbeddedRelay();
    await relay.start(port: 0);
    tmp = await Directory.systemTemp.createTemp('transfer_test_');
  });

  tearDown(() async {
    for (final s in services) {
      s.dispose();
    }
    services.clear();
    await relay.stop();
    await tmp.delete(recursive: true);
  });

  ApiConfig config() => ApiConfig('http://127.0.0.1:${relay.port}');

  /// Conecta y se registra tras auth_ok, como la app. Devuelve el clientId.
  Future<({TransferService service, String id})> join(String name) async {
    final service = TransferService();
    services.add(service);
    final welcome = Completer<String>();
    service.onWelcome = (id) {
      if (!welcome.isCompleted) welcome.complete(id);
    };
    service.onAuthOk = () => service.register(name);
    service.connect(config());
    return (service: service, id: await welcome.future.timeout(const Duration(seconds: 10)));
  }

  /// Ofrece [file] a [to] y lo envía cuando lo acepta.
  Future<void> offerAndSend(
    TransferService sender,
    String to,
    File file, {
    required String transferId,
    int? announcedSize,
    CancelToken? cancelToken,
    void Function(double)? onProgress,
  }) async {
    final accepted = Completer<void>();
    sender.onSendAccept = (id) {
      if (id == transferId && !accepted.isCompleted) accepted.complete();
    };
    sender.sendRequest(
      to: to,
      fileName: file.uri.pathSegments.last,
      fileSize: announcedSize ?? file.lengthSync(),
      mimeType: 'application/octet-stream',
      transferId: transferId,
    );
    await accepted.future.timeout(const Duration(seconds: 5));
    await sender.sendFile(
      transferId: transferId,
      file: file,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  File makeFile(String name, int size) {
    final data = Uint8List.fromList(List.generate(size, (i) => (i * 31 + 7) % 256));
    return File('${tmp.path}/$name')..writeAsBytesSync(data);
  }

  test('a multi-chunk file arrives complete and in order over an encrypted session', () async {
    final sender = await join('Emisor');
    final receiver = await join('Receptor');
    expect(sender.service.isEncrypted, true);
    expect(receiver.service.isEncrypted, true);

    final file = makeFile('payload.bin', chunkSize * 5 + 1234);
    const id = '11111111-2222-4333-8444-555555555555';
    final received = BytesBuilder(copy: false);
    final completed = Completer<void>();
    receiver.service
      ..onSendRequest = ((req) => receiver.service.accept(req.transferId))
      ..onBinaryChunk = ((_, chunk) => received.add(Uint8List.fromList(chunk)))
      ..onSendComplete = ((_) => completed.complete());

    await offerAndSend(sender.service, receiver.id, file, transferId: id);
    await completed.future.timeout(const Duration(seconds: 20));
    expect(received.takeBytes(), file.readAsBytesSync());
  });

  test('cancelling stops the send loop and no send-complete is sent', () async {
    final sender = await join('Emisor');
    final receiver = await join('Receptor');
    var completeSeen = false;
    receiver.service
      ..onSendRequest = ((req) => receiver.service.accept(req.transferId))
      ..onSendComplete = ((_) => completeSeen = true);

    final token = CancelToken();
    await expectLater(
      offerAndSend(
        sender.service,
        receiver.id,
        makeFile('big.bin', chunkSize * 20),
        transferId: '99999999-2222-4333-8444-555555555555',
        cancelToken: token,
        onProgress: (p) {
          if (p > 0.2) token.cancel();
        },
      ),
      throwsA(isA<TransferAbortedException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(completeSeen, false);
  });

  test('server mode without token triggers onAuthRequired (4401)', () async {
    await relay.startServerMode();
    final service = TransferService();
    services.add(service);
    final authRequired = Completer<void>();
    service.onAuthRequired = authRequired.complete;
    service.connect(config());
    await authRequired.future.timeout(const Duration(seconds: 5));
  });

  group('TransferController receiving', () {
    late TransferController controller;
    final snackbars = <String>[];

    Future<String> startController({bool accept = true}) async {
      snackbars.clear();
      controller = TransferController(
        transferService: TransferService(),
        deviceNameService: DeviceNameService(),
        notificationService: NotificationService(),
        receivedFilesService: ReceivedFilesService(Directory('${tmp.path}/recibidos')),
        showSnackBar: (m, {isError = false, actionLabel, onAction}) => snackbars.add(m),
        showIncomingDialog: (_, _) async => accept,
      );
      addTearDown(controller.dispose);
      await controller.initTransfer();
      final welcome = Completer<void>();
      controller.addListener(() {
        if (controller.myClientId != null && !welcome.isCompleted) welcome.complete();
      });
      await controller.connectWebSocket(config(), onAuthOk: () {});
      await welcome.future.timeout(const Duration(seconds: 10));
      return controller.myClientId!;
    }

    Future<List<String>> receivedNames() async =>
        (await ReceivedFilesService(Directory('${tmp.path}/recibidos')).listFiles())
            .map((f) => f.name)
            .toList();

    test('accepted file is saved to disk with the sanitized name', () async {
      final receiverId = await startController();
      final sender = await join('Emisor');
      final file = makeFile('foto.jpg', chunkSize * 2 + 10);

      await offerAndSend(sender.service, receiverId, file,
          transferId: 'aaaaaaaa-2222-4333-8444-555555555555');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await receivedNames(), ['foto.jpg']);
      final saved = File('${tmp.path}/recibidos/foto.jpg');
      expect(saved.readAsBytesSync(), file.readAsBytesSync());
      expect(controller.activeTransfer, isNull);
    });

    test('rejected request reaches the sender', () async {
      final receiverId = await startController(accept: false);
      final sender = await join('Emisor');
      final rejected = Completer<void>();
      sender.service.onSendReject = (_, _) => rejected.complete();
      sender.service.sendRequest(
        to: receiverId, fileName: 'x.bin', fileSize: 1,
        mimeType: 'application/octet-stream',
        transferId: 'bbbbbbbb-2222-4333-8444-555555555555',
      );
      await rejected.future.timeout(const Duration(seconds: 5));
    });

    test('a file shorter than announced is discarded', () async {
      final receiverId = await startController();
      final sender = await join('Emisor');
      final file = makeFile('corto.bin', 1000);

      await offerAndSend(sender.service, receiverId, file,
          transferId: 'cccccccc-2222-4333-8444-555555555555', announcedSize: 5000);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await receivedNames(), isEmpty);
      expect(snackbars.last, contains('incompleto'));
    });
  });

  group('DirectTransferPool', () {
    test('resolves the relay owner, reuses the connection and routes events', () async {
      final owner = await join('Dueño');
      final pool = DirectTransferPool();
      addTearDown(pool.disposeAll);
      var opened = 0;
      final requestSeen = Completer<void>();
      pool.onConnectionOpened = (service) {
        opened++;
        service.onSendRequest = (_) => requestSeen.complete();
      };

      final conn = await pool.getConnection(config().baseUrl, 'Visitante');
      expect(conn, isNotNull);
      expect(conn!.targetClientId, owner.id);

      final again = await pool.getConnection(config().baseUrl, 'Visitante');
      expect(identical(again!.service, conn.service), true);
      expect(opened, 1);

      owner.service.sendRequest(
        to: conn.service.clientId!, fileName: 'a.png', fileSize: 1,
        mimeType: 'image/png', transferId: 'dddddddd-2222-4333-8444-555555555555',
      );
      await requestSeen.future.timeout(const Duration(seconds: 5));
    });

    test('returns null when the relay requires a PIN', () async {
      await relay.startServerMode();
      final pool = DirectTransferPool();
      addTearDown(pool.disposeAll);
      expect(await pool.getConnection(config().baseUrl, 'Visitante'), isNull);
    });
  });
}
