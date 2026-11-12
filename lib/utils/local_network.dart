import 'dart:io';
import '../services/app_logger.dart';

/// Devuelve la IPv4 de la red local (wifi / ethernet) del dispositivo.
///
/// Compartida por el relay embebido y el descubrimiento para que ambos usen la
/// misma regla. Prioriza interfaces wifi/ethernet con direcciones privadas
/// (RFC 1918) y descarta link-local (169.254.x.x), datos móviles
/// (rmnet/pdp/ccmni) y VPN (tun/ppp/ipsec).
Future<String?> getLocalIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    final candidates = <({String address, int score})>[];
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      if (_isExcludedInterface(name)) continue;
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback || ip.startsWith('169.254.')) continue;
        if (!isPrivateIpv4(ip)) continue;
        var score = 0;
        if (name.startsWith('wlan') || name.startsWith('en') || name.startsWith('eth')) {
          score += 2;
        }
        if (ip.startsWith('192.168.')) score += 1;
        candidates.add((address: ip, score: score));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.address;
  } catch (e) {
    AppLogger.instance.error('local_network: error al obtener IP local', error: e);
    return null;
  }
}

bool _isExcludedInterface(String name) {
  const prefixes = ['rmnet', 'pdp', 'ccmni', 'tun', 'ppp', 'ipsec', 'utun', 'dummy', 'docker', 'veth'];
  return prefixes.any(name.startsWith);
}

/// true para 10.0.0.0/8, 172.16.0.0/12 y 192.168.0.0/16.
bool isPrivateIpv4(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  return false;
}
