import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/services/discovery_service.dart';

Future<HttpServer> healthServer(Object body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  });
  return server;
}

void main() {
  final service = DiscoveryService();

  test('probe recognizes SrvFiles servers and reads relay flags', () async {
    final server = await healthServer({
      'status': 'ok', 'app': 'SrvFiles', 'appName': 'Tel de Ana',
      'relay': true, 'serverMode': false,
    });
    addTearDown(() => server.close(force: true));

    final found = await service.probe('http://127.0.0.1:${server.port}');
    expect(found, isNotNull);
    expect(found!.appName, 'Tel de Ana');
    expect(found.acceptsDirectTransfer, true); // relay sin PIN
    expect(found.servesFiles, false); // no tiene archivos que explorar
  });

  test('desktop server serves files but does not accept direct transfers', () async {
    final server = await healthServer({'status': 'ok', 'app': 'srvfiles'});
    addTearDown(() => server.close(force: true));

    final found = await service.probe('http://127.0.0.1:${server.port}');
    expect(found!.servesFiles, true);
    expect(found.acceptsDirectTransfer, false);
  });

  test('probe rejects other apps, errors and unreachable hosts', () async {
    final other = await healthServer({'status': 'ok', 'app': 'otra-app'});
    final failing = await healthServer({'status': 'ok', 'app': 'srvfiles'}, status: 500);
    addTearDown(() async {
      await other.close(force: true);
      await failing.close(force: true);
    });

    expect(await service.probe('http://127.0.0.1:${other.port}'), isNull);
    expect(await service.probe('http://127.0.0.1:${failing.port}'), isNull);
    expect(
      await service.probe('http://127.0.0.1:1', timeout: const Duration(milliseconds: 300)),
      isNull,
    );
  });
}
