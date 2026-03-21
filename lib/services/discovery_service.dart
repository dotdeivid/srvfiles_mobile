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
  /// Escanea toda la subred local buscando servidores SrvFiles.
  /// Obtiene la IP del dispositivo, infiere la subred (e.g. 192.168.1.)
  /// y prueba las 254 direcciones en paralelo con timeout corto.
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

    // Prueba los 254 hosts en paralelo con timeout de 800ms cada uno
    final futures = List.generate(254, (i) async {
      final ip = '$subnet${i + 1}';
      if (ip == localIp) return null; // Saltar self
      final url = 'http://$ip:$_backendPort';
      final ok = await _probe(url);
      if (!ok) return null;
      debugPrint('[Discovery] Servidor encontrado → $url');
      return DiscoveredServer(ip: ip, url: url, appName: 'SrvFiles');
    });

    final results = await Future.wait(futures);
    return results.whereType<DiscoveredServer>().toList();
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

  /// Intenta conectar a un servidor específico verificando su health endpoint.
  /// Valida que la respuesta sea específicamente de un servidor SrvFiles.
  Future<bool> tryConnect(String serverUrl) async {
    final uri = Uri.parse('$serverUrl/api/health');
    debugPrint('[Discovery] tryConnect → $uri');
    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 3));
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

  // ─── Privados ──────────────────────────────────────────────────────

  /// Probe rápido para el scan LAN (timeout 800ms, sin logs verbosos).
  Future<bool> _probe(String serverUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/api/health'))
          .timeout(const Duration(milliseconds: 800));
      if (response.statusCode != 200) return false;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['app'] as String?)?.toLowerCase() == 'srvfiles' &&
          json['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Obtiene la IP local del dispositivo en la red WiFi/LAN.
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      // Preferir 192.168.x.x o 10.x.x.x
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      // Fallback: primera dirección no-loopback
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
