import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/models/app_config.dart';
import 'package:srvfiles_mobile/models/disk_stats.dart';
import 'package:srvfiles_mobile/models/file_info.dart';
import 'package:srvfiles_mobile/models/transfer_client.dart';
import 'package:srvfiles_mobile/models/transfer_request.dart';

/// Los modelos llegan de servidores de distintas versiones: un campo ausente
/// no debe tirar abajo toda la lista.
void main() {
  test('fromJson tolerates missing fields', () {
    final file = FileInfo.fromJson({'name': 'a.txt'});
    expect(file.size, 0);
    expect(file.createdAt, '');

    final client = TransferClient.fromJson({'clientId': 'c1'});
    expect(client.receiving, false);
    expect(client.deviceType, 'desktop');
    expect(client.isOwner, false);

    final config = AppConfig.fromJson({'lanIp': '192.168.1.2'});
    expect(config.port, 3001);
    expect(config.frontendPort, 3001);
    expect(config.maxFileSizeMb, 0);

    final request = IncomingTransferRequest.fromJson({'transferId': 't1'});
    expect(request.fileSize, 0);
    expect(request.mimeType, 'application/octet-stream');
  });

  test('fromJson reads present fields', () {
    final config = AppConfig.fromJson({
      'appName': 'PC',
      'lanIp': '192.168.1.10',
      'port': 3001,
      'frontendPort': 5173,
      'maxFileSizeMb': 100,
      'lanUrl': 'http://192.168.1.10:3001',
    });
    expect(config.frontendPort, 5173);
    expect(config.maxFileSizeMb, 100);

    final client = TransferClient.fromJson({
      'clientId': 'c1', 'appName': 'Tel', 'receiving': true,
      'ip': '1.2.3.4', 'deviceType': 'mobile', 'isOwner': true,
    });
    expect(client.isMobile, true);
    expect(client.isOwner, true);
  });

  test('DiskStats thresholds', () {
    expect(const DiskStats(total: 0, used: 0, free: 0).usedPercent, 0);
    expect(const DiskStats(total: 100, used: 85, free: 15).isWarning, true);
    expect(const DiskStats(total: 100, used: 85, free: 15).isCritical, false);
    expect(const DiskStats(total: 100, used: 96, free: 4).isCritical, true);
  });
}
