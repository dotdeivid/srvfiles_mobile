import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    late ApiConfig config;

    setUp(() {
      config = ApiConfig('http://192.168.1.10:3001');
    });

    test('filesUrl', () {
      expect(config.filesUrl, 'http://192.168.1.10:3001/api/files');
    });

    test('uploadUrl', () {
      expect(config.uploadUrl, 'http://192.168.1.10:3001/api/files/upload');
    });

    test('statsUrl', () {
      expect(config.statsUrl, 'http://192.168.1.10:3001/api/files/stats');
    });

    test('configUrl', () {
      expect(config.configUrl, 'http://192.168.1.10:3001/api/config');
    });

    test('healthUrl', () {
      expect(config.healthUrl, 'http://192.168.1.10:3001/api/health');
    });

    test('discoveryScanUrl', () {
      expect(config.discoveryScanUrl,
          'http://192.168.1.10:3001/api/discovery/scan');
    });

    test('wsUrl replaces http with ws', () {
      expect(config.wsUrl, 'ws://192.168.1.10:3001/ws');
    });

    test('wsUrl replaces https with wss', () {
      final secureConfig = ApiConfig('https://example.com:3001');
      expect(secureConfig.wsUrl, 'wss://example.com:3001/ws');
    });

    test('downloadUrl encodes filename', () {
      expect(
        config.downloadUrl('my file.pdf'),
        'http://192.168.1.10:3001/api/files/download/my%20file.pdf',
      );
    });

    test('downloadUrl handles special chars', () {
      expect(
        config.downloadUrl('foto (1).jpg'),
        'http://192.168.1.10:3001/api/files/download/foto%20(1).jpg',
      );
    });
  });
}
