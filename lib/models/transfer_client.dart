class TransferClient {
  final String clientId;
  final String appName;
  final bool receiving;
  final String ip;
  final String deviceType;
  final bool isServer;
  /// true si este cliente es el dueño del relay (conectó desde localhost).
  final bool isOwner;

  /// true si soporta cifrado de extremo a extremo (obligatorio para transferir).
  final bool e2e;

  const TransferClient({
    required this.clientId,
    required this.appName,
    required this.receiving,
    required this.ip,
    this.deviceType = 'desktop',
    this.isServer = false,
    this.isOwner = false,
    this.e2e = false,
  });

  factory TransferClient.fromJson(Map<String, dynamic> json) => TransferClient(
        clientId: (json['clientId'] as String?) ?? '',
        appName: (json['appName'] as String?) ?? 'Dispositivo',
        receiving: (json['receiving'] as bool?) ?? false,
        ip: (json['ip'] as String?) ?? '',
        deviceType: (json['deviceType'] as String?) ?? 'desktop',
        isServer: (json['isServer'] as bool?) ?? false,
        isOwner: (json['isOwner'] as bool?) ?? false,
        e2e: (json['e2e'] as bool?) ?? false,
      );

  bool get isMobile => deviceType == 'mobile';
}
