import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _backendPort = 3001;

class DiscoveredServer {
  final String ip;
  final String url;
  final String appName;

  const DiscoveredServer({
    required this.ip,
    required this.url,
    required this.appName,
  });

  factory DiscoveredServer.fromJson(Map<String, dynamic> json) =>
      DiscoveredServer(
        ip: json['ip'] as String,
        url: json['url'] as String,
        appName: json['appName'] as String,
      );
}

class DiscoveryService {
  /// Prueba una URL y devuelve un [DiscoveredServer] si es un servidor SrvFiles
  /// válido, o null si no responde o no es SrvFiles.
  Future<DiscoveredServer?> probe(
    String serverUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final uri = Uri.parse('$serverUrl/api/health');
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if ((json['app'] as String?)?.toLowerCase() != 'srvfiles' ||
          json['status'] != 'ok') return null;
      final ip = uri.host;
      final appName =
          (json['appName'] as String?) ?? (json['app'] as String?) ?? 'SrvFiles';
      return DiscoveredServer(ip: ip, url: serverUrl, appName: appName);
    } catch (_) {
      return null;
    }
  }

  /// Verifica si una URL es un servidor SrvFiles activo.
  Future<bool> tryConnect(String serverUrl) async {
    final uri = Uri.parse('$serverUrl/api/health');
    debugPrint('[Discovery] tryConnect → $uri');
    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 3));
      debugPrint('[Discovery] status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) return false;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = (json['app'] as String?)?.toLowerCase() == 'srvfiles' &&
          json['status'] == 'ok';
      debugPrint('[Discovery] SrvFiles check → $ok');
      return ok;
    } catch (e) {
      debugPrint('[Discovery] error → $e');
      return false;
    }
  }

  /// Escanea toda la subred local buscando servidores SrvFiles.
  /// Obtiene la IP del dispositivo, infiere la subred y prueba las 254
  /// direcciones en paralelo con timeout corto.
  Future<List<DiscoveredServer>> scanLan() async {
    final localIp = await _getLocalIp();
    if (localIp == null) {
      debugPrint('[Discovery] No se pudo obtener la IP local');
      return [];
    }

    final parts = localIp.split('.');
    if (parts.length != 4) return [];
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.';
    debugPrint('[Discovery] Escaneando subred $subnet* (IP local: $localIp)');

    final futures = List.generate(254, (i) async {
      final ip = '$subnet${i + 1}';
      if (ip == localIp) return null;
      final url = 'http://$ip:$_backendPort';
      return probe(url, timeout: const Duration(milliseconds: 800));
    });

    final results = await Future.wait(futures);
    final found = results.whereType<DiscoveredServer>().toList();
    debugPrint('[Discovery] Servidores encontrados: ${found.length}');
    return found;
  }

  /// Escanea la red usando el endpoint del servidor ya conocido (backup).
  Future<List<DiscoveredServer>> scanNetwork(String serverUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/api/discovery/scan'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => DiscoveredServer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Privados ──────────────────────────────────────────────────────

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
