import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/features/transfer/transfer_controller.dart';
import 'package:srvfiles_mobile/services/device_name_service.dart';
import 'package:srvfiles_mobile/services/direct_transfer_pool.dart';
import 'package:srvfiles_mobile/services/e2e_service.dart';
import 'package:srvfiles_mobile/services/embedded_relay.dart';
import 'package:srvfiles_mobile/services/notification_service.dart';
import 'package:srvfiles_mobile/services/received_files_service.dart';
import 'package:srvfiles_mobile/services/transfer_service.dart';

/// Transferencias P2P de punta a punta a través del relay embebido, con
/// cifrado del canal y cifrado de extremo a extremo obligatorio.
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

  /// Emisor "a mano": ofrece [file], deriva la sesión E2E al llegar la clave
  /// del receptor y envía cuando acepta. Devuelve el código de verificación.
  Future<String> offerAndSend(
    TransferService sender,
    String to,
    File file, {
    required String transferId,
    int? announcedSize,
    CancelToken? cancelToken,
    void Function(double)? onProgress,
  }) async {
    final keys = E2EKeyPair.generate();
    E2ESession? session;
    final keyed = Completer<void>();
    final accepted = Completer<void>();
    sender.onSendKey = (id, key) async {
      if (id != transferId) return;
      session = await E2ESession.derive(
        ownPrivateKey: keys.privateKey,
        peerPublicKey: key,
        senderPublicKey: keys.publicKey,
        receiverPublicKey: key,
        transferId: transferId,
      );
      if (!keyed.isCompleted) keyed.complete();
    };
    sender.onSendAccept = (id) {
      if (id == transferId && !accepted.isCompleted) accepted.complete();
    };
    sender.sendRequest(
      to: to,
      fileName: file.uri.pathSegments.last,
      fileSize: announcedSize ?? file.lengthSync(),
      mimeType: 'application/octet-stream',
      transferId: transferId,
      e2ePublicKey: keys.publicKey,
    );
    await keyed.future.timeout(const Duration(seconds: 5));
    await accepted.future.timeout(const Duration(seconds: 5));
    await sender.sendFile(
      transferId: transferId,
      file: file,
      e2e: session!,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
    return session!.sas;
  }

  File makeFile(String name, int size) {
    final data = Uint8List.fromList(List.generate(size, (i) => (i * 31 + 7) % 256));
    return File('${tmp.path}/$name')..writeAsBytesSync(data);
  }

  test('server mode without token triggers onAuthRequired (4401)', () async {
    await relay.startServerMode();
    final service = TransferService();
    services.add(service);
    final authRequired = Completer<void>();
    service.onAuthRequired = authRequired.complete;
    service.connect(config());
    await authRequired.future.timeout(const Duration(seconds: 5));
  });

  test('the relay rejects requests without an E2E key', () async {
    final sender = await join('Emisor');
    final receiver = await join('Receptor');
    final rejected = Completer<String?>();
    sender.service.onSendReject = (_, reason) => rejected.complete(reason);
    // Petición "vieja", sin e2e: se arma a mano por debajo del TransferService.
    sender.service.sendRequest(
      to: receiver.id, fileName: 'x', fileSize: 1, mimeType: 'x',
      transferId: 'aaaaaaaa-0000-4000-8000-000000000000', e2ePublicKey: 'no-es-una-clave',
    );
    expect(await rejected.future.timeout(const Duration(seconds: 5)), 'e2e-required');
  });

  group('TransferController receiving', () {
    late TransferController controller;
    final snackbars = <String>[];
    final shownCodes = <String>[];

    Future<String> startController({bool accept = true}) async {
      snackbars.clear();
      shownCodes.clear();
      controller = TransferController(
        transferService: TransferService(),
        deviceNameService: DeviceNameService(),
        notificationService: NotificationService(),
        receivedFilesService: ReceivedFilesService(Directory('${tmp.path}/recibidos')),
        showSnackBar: (m, {isError = false, actionLabel, onAction}) => snackbars.add(m),
        showIncomingDialog: (_, sas, _) async {
          shownCodes.add(sas);
          return accept;
        },
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

    test('a multi-chunk file arrives E2E-encrypted, intact, with matching codes', () async {
      final receiverId = await startController();
      final sender = await join('Emisor');
      final file = makeFile('foto.jpg', chunkSize * 3 + 10);

      final senderCode = await offerAndSend(sender.service, receiverId, file,
          transferId: 'bbbbbbbb-2222-4333-8444-555555555555');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(shownCodes, [senderCode]); // el receptor vio el mismo código
      expect(await receivedNames(), ['foto.jpg']);
      expect(File('${tmp.path}/recibidos/foto.jpg').readAsBytesSync(), file.readAsBytesSync());
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
        transferId: 'cccccccc-2222-4333-8444-555555555555',
        e2ePublicKey: E2EKeyPair.generate().publicKey,
      );
      await rejected.future.timeout(const Duration(seconds: 5));
    });

    // El marcador final cifrado declara el tamaño real: no coincide con el anunciado.
    test('a file that does not match the announced size is discarded', () async {
      final receiverId = await startController();
      final sender = await join('Emisor');
      await offerAndSend(sender.service, receiverId, makeFile('corto.bin', 1000),
          transferId: 'dddddddd-2222-4333-8444-555555555555', announcedSize: 5000);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await receivedNames(), isEmpty);
      expect(snackbars.last, contains('incompleto'));
    });
  });

  test('cancelling stops the send loop and no send-complete is sent', () async {
    final sender = await join('Emisor');
    final receiver = await join('Receptor');
    var completeSeen = false;
    receiver.service
      ..onSendRequest = ((req) => receiver.service
        ..sendKey(req.transferId, E2EKeyPair.generate().publicKey)
        ..accept(req.transferId))
      ..onSendComplete = ((_, _) => completeSeen = true);

    final token = CancelToken();
    await expectLater(
      offerAndSend(
        sender.service,
        receiver.id,
        makeFile('big.bin', chunkSize * 20),
        transferId: 'eeeeeeee-2222-4333-8444-555555555555',
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
      expect(conn.targetE2E, true);

      final again = await pool.getConnection(config().baseUrl, 'Visitante');
      expect(identical(again!.service, conn.service), true);
      expect(opened, 1);

      owner.service.sendRequest(
        to: conn.service.clientId!, fileName: 'a.png', fileSize: 1,
        mimeType: 'image/png', transferId: 'ffffffff-2222-4333-8444-555555555555',
        e2ePublicKey: E2EKeyPair.generate().publicKey,
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
