import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/models/file_info.dart';
import 'package:srvfiles_mobile/models/disk_stats.dart';
import 'package:srvfiles_mobile/models/app_config.dart';
import 'package:srvfiles_mobile/models/transfer_client.dart';
import 'package:srvfiles_mobile/models/transfer_request.dart';
import 'package:srvfiles_mobile/models/active_transfer.dart';

void main() {
  group('FileInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'name': 'foto.jpg',
        'size': 1024,
        'createdAt': '2026-03-20T10:00:00.000Z',
        'downloadUrl': '/api/files/foto.jpg',
      };

      final file = FileInfo.fromJson(json);
      expect(file.name, 'foto.jpg');
      expect(file.size, 1024);
      expect(file.createdAt, '2026-03-20T10:00:00.000Z');
      expect(file.downloadUrl, '/api/files/foto.jpg');
    });
  });

  group('DiskStats', () {
    test('fromJson parses correctly', () {
      final json = {'total': 1000000, 'used': 500000, 'free': 500000};
      final stats = DiskStats.fromJson(json);
      expect(stats.total, 1000000);
      expect(stats.used, 500000);
      expect(stats.free, 500000);
    });

    test('usedPercent calculates correctly', () {
      final stats = DiskStats(total: 1000, used: 750, free: 250);
      expect(stats.usedPercent, 75.0);
    });

    test('usedPercent is 0 when total is 0', () {
      final stats = DiskStats(total: 0, used: 0, free: 0);
      expect(stats.usedPercent, 0);
    });

    test('isWarning is true above 80%', () {
      final stats = DiskStats(total: 100, used: 85, free: 15);
      expect(stats.isWarning, true);
      expect(stats.isCritical, false);
    });

    test('isCritical is true above 95%', () {
      final stats = DiskStats(total: 100, used: 97, free: 3);
      expect(stats.isWarning, true);
      expect(stats.isCritical, true);
    });

    test('isWarning is false below 80%', () {
      final stats = DiskStats(total: 100, used: 50, free: 50);
      expect(stats.isWarning, false);
      expect(stats.isCritical, false);
    });
  });

  group('AppConfig', () {
    test('fromJson parses correctly', () {
      final json = {
        'appName': 'SrvFiles',
        'lanIp': '192.168.1.10',
        'port': 3001,
        'frontendPort': 5173,
        'maxFileSizeMb': 500,
        'lanUrl': 'http://192.168.1.10:3001',
      };

      final config = AppConfig.fromJson(json);
      expect(config.appName, 'SrvFiles');
      expect(config.lanIp, '192.168.1.10');
      expect(config.port, 3001);
      expect(config.frontendPort, 5173);
      expect(config.maxFileSizeMb, 500);
      expect(config.lanUrl, 'http://192.168.1.10:3001');
    });
  });

  group('TransferClient', () {
    test('fromJson parses correctly with deviceType', () {
      final json = {
        'clientId': 'abc-123',
        'appName': 'Rápido Zorro',
        'receiving': true,
        'ip': '192.168.1.45',
        'deviceType': 'mobile',
      };

      final client = TransferClient.fromJson(json);
      expect(client.clientId, 'abc-123');
      expect(client.appName, 'Rápido Zorro');
      expect(client.receiving, true);
      expect(client.ip, '192.168.1.45');
      expect(client.deviceType, 'mobile');
      expect(client.isMobile, true);
    });

    test('fromJson defaults deviceType to desktop when absent', () {
      final json = {
        'clientId': 'abc-456',
        'appName': 'PC Oficina',
        'receiving': false,
        'ip': '192.168.1.10',
      };

      final client = TransferClient.fromJson(json);
      expect(client.deviceType, 'desktop');
      expect(client.isMobile, false);
    });
  });

  group('IncomingTransferRequest', () {
    test('fromJson parses correctly', () {
      final json = {
        'transferId': 'transfer-001',
        'from': 'client-A',
        'fromName': 'PC Oficina',
        'fileName': 'reporte.pdf',
        'fileSize': 5242880,
        'mimeType': 'application/pdf',
      };

      final request = IncomingTransferRequest.fromJson(json);
      expect(request.transferId, 'transfer-001');
      expect(request.from, 'client-A');
      expect(request.fromName, 'PC Oficina');
      expect(request.fileName, 'reporte.pdf');
      expect(request.fileSize, 5242880);
      expect(request.mimeType, 'application/pdf');
    });
  });

  group('ActiveTransfer', () {
    test('copyWith updates progress', () {
      const transfer = ActiveTransfer(
        transferId: 't1',
        fileName: 'test.txt',
        fileSize: 1000,
        progress: 0,
        direction: TransferDirection.sending,
        peerName: 'Peer',
        peerId: 'p1',
        waiting: true,
      );

      final updated = transfer.copyWith(progress: 50, waiting: false);
      expect(updated.progress, 50);
      expect(updated.waiting, false);
      expect(updated.transferId, 't1');
      expect(updated.fileName, 'test.txt');
      expect(updated.direction, TransferDirection.sending);
    });

    test('copyWith preserves values when not specified', () {
      const transfer = ActiveTransfer(
        transferId: 't1',
        fileName: 'test.txt',
        fileSize: 1000,
        progress: 25,
        direction: TransferDirection.receiving,
        peerName: 'Peer',
        peerId: 'p1',
        waiting: false,
      );

      final updated = transfer.copyWith(progress: 75);
      expect(updated.progress, 75);
      expect(updated.waiting, false); // preserved
    });
  });
}
