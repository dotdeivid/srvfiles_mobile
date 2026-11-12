import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/api_config.dart';
import '../utils/local_network.dart';
import 'app_logger.dart';

class DiscoveredServer {
  final String ip;
  final String url;
  final String appName;

  /// true si es el relay embebido de un teléfono (acepta envío directo).
  final bool isRelay;

  /// true si ese teléfono tiene el modo servidor activo (pide PIN).
  final bool serverMode;

  /// 'mobile' o 'desktop'.
  final String deviceType;

  const DiscoveredServer({
    required this.ip,
    required this.url,
    required this.appName,
    this.isRelay = false,
    this.serverMode = false,
    this.deviceType = 'desktop',
  });

  /// true si se le puede enviar un archivo directo (relay de teléfono sin PIN).
  bool get acceptsDirectTransfer => isRelay && !serverMode;

  /// true si expone archivos (servidor de escritorio o teléfono en modo
  /// servidor). Un relay sin modo servidor no tiene archivos que explorar.
  bool get servesFiles => !isRelay || serverMode;

  bool get isMobile => deviceType == 'mobile' || isRelay;

  factory DiscoveredServer.fromJson(Map<String, dynamic> json) =>
      DiscoveredServer(
        ip: (json['ip'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
        appName: (json['appName'] as String?) ?? 'SrvFiles',
        isRelay: (json['relay'] as bool?) ?? false,
        serverMode: (json['serverMode'] as bool?) ?? false,
        deviceType: (json['deviceType'] as String?) ?? 'desktop',
      );
}

class DiscoveryService {
  /// Peticiones simultáneas durante el barrido de la subred.
  static const _scanConcurrency = 32;

  /// Prueba una URL y devuelve un [DiscoveredServer] si es un servidor SrvFiles
  /// válido, o null si no responde o no es SrvFiles.
  Future<DiscoveredServer?> probe(
    String serverUrl, {
    Duration timeout = const Duration(seconds: 3),
    HttpClient? client,
  }) async {
    final ownClient = client == null;
    final http = client ?? (HttpClient()..connectionTimeout = timeout);
    try {
      final uri = Uri.parse('$serverUrl/api/health');
      final request = await http.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      // El cuerpo de /api/health es pequeño; cortar si no lo es.
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (body.length > 16 * 1024) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      if ((json['app'] as String?)?.toLowerCase() != 'srvfiles' ||
          json['status'] != 'ok') {
        return null;
      }
      return DiscoveredServer(
        ip: uri.host,
        url: serverUrl,
        appName: (json['appName'] as String?) ?? (json['app'] as String?) ?? 'SrvFiles',
        isRelay: json['relay'] == true,
        serverMode: json['serverMode'] == true,
        deviceType: (json['deviceType'] as String?) ??
            (json['relay'] == true ? 'mobile' : 'desktop'),
      );
    } catch (_) {
      return null;
    } finally {
      if (ownClient) http.close(force: true);
    }
  }

  /// Verifica si una URL es un servidor SrvFiles activo.
  Future<bool> tryConnect(String serverUrl) async {
    final ok = await probe(serverUrl) != null;
    AppLogger.instance.debug('[Discovery] tryConnect $serverUrl → $ok');
    return ok;
  }

  /// Escanea la subred local buscando servidores SrvFiles.
  ///
  /// Prueba las direcciones de la /24 de la IP wifi con concurrencia limitada
  /// y un único cliente HTTP. [isCancelled] permite abortar el barrido (p. ej.
  /// al salir de la pantalla).
  Future<List<DiscoveredServer>> scanLan({
    int port = defaultServerPort,
    bool Function()? isCancelled,
  }) async {
    final localIp = await getLocalIpv4();
    if (localIp == null) {
      AppLogger.instance.warn('[Discovery] No se pudo obtener la IP local (¿sin wifi?)');
      return [];
    }

    final parts = localIp.split('.');
    if (parts.length != 4) return [];
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.';
    AppLogger.instance.debug('[Discovery] Escaneando subred $subnet* (IP local: $localIp)');

    const timeout = Duration(milliseconds: 800);
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 1);
    final ips = [
      for (var i = 1; i <= 254; i++)
        if ('$subnet$i' != localIp) '$subnet$i',
    ];
    final found = <DiscoveredServer>[];
    var next = 0;

    Future<void> worker() async {
      while (next < ips.length) {
        if (isCancelled?.call() ?? false) return;
        final ip = ips[next++];
        final server = await probe('http://$ip:$port', timeout: timeout, client: client);
        if (server != null) found.add(server);
      }
    }

    try {
      await Future.wait(List.generate(_scanConcurrency, (_) => worker()));
    } finally {
      client.close(force: true);
    }
    found.sort((a, b) => a.ip.compareTo(b.ip));
    AppLogger.instance.debug('[Discovery] Servidores encontrados: ${found.length}');
    return found;
  }
}
