import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/e2e_service.dart';

/// Vectores compartidos con Go y la web (srvfiles_web/docs/e2e-test-vectors.json).
void main() {
  final v = jsonDecode(File('test/fixtures/e2e-vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final transferId = v['transferId'] as String;
  final sender = E2EKeyPair.fromPrivateHex(v['sender']['privateHex'] as String);
  final receiver = E2EKeyPair.fromPrivateHex(v['receiver']['privateHex'] as String);

  Future<E2ESession> derive(E2EKeyPair own, String peer) => E2ESession.derive(
        ownPrivateKey: own.privateKey,
        peerPublicKey: peer,
        senderPublicKey: sender.publicKey,
        receiverPublicKey: receiver.publicKey,
        transferId: transferId,
      );

  test('public keys, verification code and ciphertexts match the shared vectors', () async {
    expect(sender.publicKey, v['sender']['publicKey']);
    expect(receiver.publicKey, v['receiver']['publicKey']);

    final s = await derive(sender, receiver.publicKey);
    final r = await derive(receiver, sender.publicKey);
    expect(s.sas, v['sas']);
    expect(r.sas, v['sas']);

    for (final c in (v['chunks'] as List).cast<Map<String, dynamic>>()) {
      final index = c['index'] as int;
      final plain = base64.decode(c['plaintext'] as String);
      expect(base64.encode(await s.encryptChunk(index, plain)), c['ciphertext']);
      expect(await r.decryptChunk(index, base64.decode(c['ciphertext'] as String)), plain);
    }
    final fin = v['final'] as Map<String, dynamic>;
    final decoded = await r.decryptFinal(fin['index'] as int, fin['ciphertext'] as String);
    final expected = jsonDecode(fin['plaintext'] as String) as Map<String, dynamic>;
    expect(decoded.chunks, expected['chunks']);
    expect(decoded.size, expected['size']);
    expect(decoded.name, expected['name']);
  });

  test('a chunk with the wrong index or tampered data is rejected', () async {
    final r = await derive(receiver, sender.publicKey);
    final ct = Uint8List.fromList(base64.decode((v['chunks'] as List)[0]['ciphertext'] as String));
    await expectLater(r.decryptChunk(1, ct), throwsA(anything));
    ct[0] ^= 1;
    await expectLater(r.decryptChunk(0, ct), throwsA(anything));
  });
}
