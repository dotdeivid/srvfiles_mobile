class TransferClient {
  final String clientId;
  final String appName;
  final bool receiving;
  final String ip;
  final String deviceType;
  final bool isServer;
  /// true si este cliente es el dueño del relay (conectó desde localhost).
  final bool isOwner;

  const TransferClient({
    required this.clientId,
    required this.appName,
    required this.receiving,
    required this.ip,
    this.deviceType = 'desktop',
    this.isServer = false,
    this.isOwner = false,
  });

  factory TransferClient.fromJson(Map<String, dynamic> json) => TransferClient(
        clientId: json['clientId'] as String,
        appName: json['appName'] as String,
        receiving: json['receiving'] as bool,
        ip: json['ip'] as String,
        deviceType: (json['deviceType'] as String?) ?? 'desktop',
        isServer: (json['isServer'] as bool?) ?? false,
        isOwner: (json['isOwner'] as bool?) ?? false,
      );

  bool get isMobile => deviceType == 'mobile';
}
