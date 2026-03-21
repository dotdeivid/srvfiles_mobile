class AppConfig {
  final String appName;
  final String lanIp;
  final int port;
  final int frontendPort;
  final int maxFileSizeMb;
  final String lanUrl;

  const AppConfig({
    required this.appName,
    required this.lanIp,
    required this.port,
    required this.frontendPort,
    required this.maxFileSizeMb,
    required this.lanUrl,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        appName: json['appName'] as String,
        lanIp: json['lanIp'] as String,
        port: json['port'] as int,
        frontendPort: json['frontendPort'] as int,
        maxFileSizeMb: json['maxFileSizeMb'] as int,
        lanUrl: json['lanUrl'] as String,
      );
}
