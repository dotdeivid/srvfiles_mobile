import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/crypto_service.dart';

void main() {
  Future<({SessionCipher client, SessionCipher server})> exchange() async {
    late String clientPub;
    late ({SessionCipher cipher, String serverPublicKey}) serverSide;
    final client = await CryptoService.clientKeyExchange(
      sendPublicKey: (pub) => clientPub = pub,
      waitForPeerKey: () async {
        serverSide = await CryptoService.serverKeyExchange(clientPub);
        return serverSide.serverPublicKey;
      },
    );
    return (client: client!, server: serverSide.cipher);
  }

  test('client and server derive the same key (JSON and binary)', () async {
    final ciphers = await exchange();

    final json = await ciphers.client.encryptJson('{"type":"hello"}');
    expect(await ciphers.server.decryptJson(json['iv']!, json['data']!), '{"type":"hello"}');

    final payload = Uint8List.fromList(List.generate(300000, (i) => i % 256));
    expect(await ciphers.client.decryptBinary(await ciphers.server.encryptBinary(payload)), payload);
  });

  test('empty peer key (timeout) yields no cipher', () async {
    final cipher = await CryptoService.clientKeyExchange(
      sendPublicKey: (_) {},
      waitForPeerKey: () async => '',
    );
    expect(cipher, isNull);
  });

  test('rejects malformed and off-curve public keys', () async {
    final offCurve = Uint8List(65)..[0] = 0x04..[64] = 1;
    expect(() => CryptoService.serverKeyExchange(base64.encode(offCurve)), throwsArgumentError);
    expect(() => CryptoService.serverKeyExchange(base64.encode(Uint8List(33))), throwsArgumentError);
  });

  test('tampered ciphertext fails authentication', () async {
    final ciphers = await exchange();
    final frame = await ciphers.client.encryptBinary(Uint8List.fromList([1, 2, 3, 4]));
    frame[frame.length - 1] ^= 0xff;
    expect(() => ciphers.server.decryptBinary(frame), throwsA(anything));
  });
}
