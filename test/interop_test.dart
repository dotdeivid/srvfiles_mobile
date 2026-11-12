import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/services/e2e_service.dart';
import 'package:srvfiles_mobile/services/transfer_service.dart';

/// Interoperabilidad con el backend Go de srvfiles_web (CI: job "interop").
/// Se activa con `SRVFILES_INTEROP_URL=http://localhost:PUERTO`.
void main() {
  final server = Platform.environment['SRVFILES_INTEROP_URL'];

  Future<String> login() async {
    final http = HttpClient();
    try {
      final pinRes = await (await http.getUrl(Uri.parse('$server/api/pin'))).close();
      final pin = (jsonDecode(await pinRes.transform(utf8.decoder).join()) as Map)['pin'];
      final req = await http.postUrl(Uri.parse('$server/api/auth'));
      req.write(jsonEncode({'pin': pin}));
      final res = await req.close();
      return (jsonDecode(await res.transform(utf8.decoder).join()) as Map)['token'] as String;
    } finally {
      http.close();
    }
  }

  Future<({TransferService service, String id})> join(String name) async {
    final service = TransferService()..setToken(await login());
    final welcome = Completer<String>();
    service.onWelcome = (id) => welcome.isCompleted ? null : welcome.complete(id);
    service.onAuthOk = () => service.register(name);
    service.connect(ApiConfig(server!));
    return (service: service, id: await welcome.future.timeout(const Duration(seconds: 10)));
  }

  test('E2E transfer through the Go relay', () async {
    final sender = await join('Interop móvil emisor');
    final receiver = await join('Interop móvil receptor');
    addTearDown(() {
      sender.service.dispose();
      receiver.service.dispose();
    });
    expect(sender.service.isEncrypted, true); // cifrado del canal con Go

    final tmp = await Directory.systemTemp.createTemp('interop_');
    addTearDown(() => tmp.delete(recursive: true));
    final data = Uint8List.fromList(List.generate(chunkSize * 2 + 77, (i) => (i * 13) % 256));
    final file = File('${tmp.path}/interop.bin')..writeAsBytesSync(data);
    const transferId = '12345678-2222-4333-8444-555555555555';

    // Receptor
    E2ESession? receiverSession;
    final received = BytesBuilder(copy: false);
    var index = 0;
    final chunks = <Uint8List>[];
    final completed = Completer<String?>();
    receiver.service
      ..onSendRequest = ((req) async {
        final own = E2EKeyPair.generate();
        receiverSession = await E2ESession.derive(
          ownPrivateKey: own.privateKey, peerPublicKey: req.senderPublicKey,
          senderPublicKey: req.senderPublicKey, receiverPublicKey: own.publicKey, transferId: req.transferId,
        );
        receiver.service
          ..sendKey(req.transferId, own.publicKey)
          ..accept(req.transferId);
      })
      ..onBinaryChunk = ((_, chunk) => chunks.add(Uint8List.fromList(chunk)))
      ..onSendComplete = ((_, finalMarker) => completed.complete(finalMarker));

    // Emisor
    final keys = E2EKeyPair.generate();
    E2ESession? senderSession;
    final accepted = Completer<void>();
    sender.service
      ..onSendKey = ((id, key) async {
        senderSession = await E2ESession.derive(
          ownPrivateKey: keys.privateKey, peerPublicKey: key,
          senderPublicKey: keys.publicKey, receiverPublicKey: key, transferId: id,
        );
      })
      ..onSendAccept = ((_) => accepted.complete());
    sender.service.sendRequest(
      to: receiver.id, fileName: 'interop.bin', fileSize: data.length,
      mimeType: 'application/octet-stream', transferId: transferId, e2ePublicKey: keys.publicKey,
    );
    await accepted.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sender.service.sendFile(transferId: transferId, file: file, e2e: senderSession!, fileName: 'interop.bin');

    final finalMarker = await completed.future.timeout(const Duration(seconds: 20));
    expect(senderSession!.sas, receiverSession!.sas);
    for (final c in chunks) {
      received.add(await receiverSession!.decryptChunk(index++, c));
    }
    final fin = await receiverSession!.decryptFinal(index, finalMarker!);
    expect(fin.chunks, index);
    expect(fin.size, data.length);
    expect(received.takeBytes(), data);
  }, skip: server == null ? 'SRVFILES_INTEROP_URL no definido' : false, timeout: const Timeout(Duration(seconds: 60)));
}
