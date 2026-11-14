import '../config/api_config.dart';

class AppConfig {
  final String appName;
  final String lanIp;
  final int port;
  final int frontendPort;
  /// Puerto HTTPS para navegadores (0 = el servidor no tiene HTTPS).
  final int httpsPort;
  final int maxFileSizeMb;
  final int previewMaxFileSizeMb;
  final String lanUrl;

  const AppConfig({
    required this.appName,
    required this.lanIp,
    required this.port,
    required this.frontendPort,
    this.httpsPort = 0,
    required this.maxFileSizeMb,
    this.previewMaxFileSizeMb = 50,
    required this.lanUrl,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final port = (json['port'] as num?)?.toInt() ?? defaultServerPort;
    return AppConfig(
      appName: (json['appName'] as String?) ?? 'SrvFiles',
      lanIp: (json['lanIp'] as String?) ?? '',
      port: port,
      frontendPort: (json['frontendPort'] as num?)?.toInt() ?? port,
      httpsPort: (json['httpsPort'] as num?)?.toInt() ?? 0,
      maxFileSizeMb: (json['maxFileSizeMb'] as num?)?.toInt() ?? 0,
      previewMaxFileSizeMb: (json['previewMaxFileSizeMb'] as num?)?.toInt() ?? 50,
      lanUrl: (json['lanUrl'] as String?) ?? '',
    );
  }

  /// Dirección para abrir desde un navegador: la HTTPS si el servidor la
  /// tiene (sin contexto seguro el navegador no puede transferir archivos).
  String get browserUrl =>
      httpsPort > 0 ? 'https://$lanIp:$httpsPort' : 'http://$lanIp:$frontendPort';
}
