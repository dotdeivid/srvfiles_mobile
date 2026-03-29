class AppConfig {
  final String appName;
  final String lanIp;
  final int port;
  final int frontendPort;
  final int maxFileSizeMb;
  final int previewMaxFileSizeMb;
  final String lanUrl;

  const AppConfig({
    required this.appName,
    required this.lanIp,
    required this.port,
    required this.frontendPort,
    required this.maxFileSizeMb,
    this.previewMaxFileSizeMb = 50,
    required this.lanUrl,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final port = (json['port'] as num).toInt();
    return AppConfig(
      appName: (json['appName'] as String?) ?? 'SrvFiles',
      lanIp: (json['lanIp'] as String?) ?? '',
      port: port,
      frontendPort: (json['frontendPort'] as num?)?.toInt() ?? port,
      maxFileSizeMb: (json['maxFileSizeMb'] as num?)?.toInt() ?? 0,
      previewMaxFileSizeMb: (json['previewMaxFileSizeMb'] as num?)?.toInt() ?? 50,
      lanUrl: (json['lanUrl'] as String?) ?? '',
    );
  }
}
