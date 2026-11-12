import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/config/api_config.dart';
import 'package:srvfiles_mobile/utils/file_names.dart';
import 'package:srvfiles_mobile/utils/format.dart';
import 'package:srvfiles_mobile/utils/local_network.dart';
import 'package:srvfiles_mobile/utils/server_url.dart';

/// Funciones puras con casos límite que ya causaron bugs.
void main() {
  test('sanitizeFileName strips paths and reserved characters, keeps accents', () {
    expect(sanitizeFileName('../../etc/passwd'), 'passwd');
    expect(sanitizeFileName(r'..\..\windows\system.ini'), 'system.ini');
    expect(sanitizeFileName('file:name?.txt'), 'file_name_.txt');
    expect(sanitizeFileName('año señal.txt'), 'año señal.txt');
    expect(sanitizeFileName(''), 'archivo');
    expect(sanitizeFileName('/'), 'archivo');
  });

  test('resolveInside rejects traversal and separators', () {
    final dir = Directory.systemTemp.createTempSync('resolve_inside_');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(resolveInside(dir, 'foto.jpg')?.path, endsWith('foto.jpg'));
    for (final bad in ['../secret', '..', 'a/b', r'a\b', '']) {
      expect(resolveInside(dir, bad), isNull, reason: bad);
    }
  });

  test('uniqueFileIn adds the suffix after the name, also for dotfiles', () async {
    final dir = Directory.systemTemp.createTempSync('unique_file_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/doc.pdf').writeAsStringSync('x');
    File('${dir.path}/.gitignore').writeAsStringSync('x');
    expect((await uniqueFileIn(dir, 'doc.pdf')).path, endsWith('doc (1).pdf'));
    expect((await uniqueFileIn(dir, '.gitignore')).path, endsWith('.gitignore (1)'));
    expect((await uniqueFileIn(dir, 'nuevo.txt')).path, endsWith('nuevo.txt'));
  });

  test('formatBytes', () {
    const cases = {
      0: '0 B',
      -5: '0 B',
      500: '500 B',
      1536: '1.5 KB',
      1048576: '1 MB',
      1073741824: '1 GB',
    };
    cases.forEach((bytes, expected) => expect(formatBytes(bytes), expected));
    expect(formatBytes(1 << 62), endsWith('EB')); // no se sale de la tabla
  });

  test('formatDate works without locale initialization and tolerates bad input', () {
    expect(formatDate('2026-03-17T12:30:00'), '17 mar 2026, 12:30');
    expect(formatDate('no-es-fecha'), '');
  });

  test('normalizeServerUrl', () {
    expect(normalizeServerUrl('192.168.1.5'), 'http://192.168.1.5:3001');
    expect(normalizeServerUrl('192.168.1.5:8080/'), 'http://192.168.1.5:8080');
    expect(normalizeServerUrl('http://host:3001/ruta'), 'http://host:3001');
    expect(normalizeServerUrl('   '), isNull);
    expect(normalizeServerUrl('ftp://host'), isNull);
  });

  test('sameHost compares hosts, not substrings', () {
    expect(sameHost('http://192.168.1.1:3001', 'http://192.168.1.10:3001'), false);
    expect(sameHost('http://192.168.1.1:3001', 'http://192.168.1.1:5173'), true);
  });

  test('isPrivateIpv4 accepts RFC 1918 ranges only', () {
    expect(isPrivateIpv4('192.168.0.10'), true);
    expect(isPrivateIpv4('10.1.2.3'), true);
    expect(isPrivateIpv4('172.16.0.1'), true);
    expect(isPrivateIpv4('172.32.0.1'), false);
    expect(isPrivateIpv4('100.64.0.1'), false); // CGNAT de operadores
  });

  test('ApiConfig encodes download names and maps http(s) to ws(s)', () {
    final config = ApiConfig('http://192.168.1.10:3001');
    expect(config.downloadUrl('foto (1).jpg'),
        'http://192.168.1.10:3001/api/files/download/foto%20(1).jpg');
    expect(config.wsUrl, 'ws://192.168.1.10:3001/ws');
    expect(ApiConfig('https://example.com').wsUrl, 'wss://example.com/ws');
  });
}
