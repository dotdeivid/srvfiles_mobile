class IncomingTransferRequest {
  final String transferId;
  final String from;
  final String fromName;
  final String fileName;
  final int fileSize;
  final String mimeType;

  /// Clave pública E2E del emisor (base64), o '' si no la mandó.
  final String senderPublicKey;

  const IncomingTransferRequest({
    required this.transferId,
    required this.from,
    required this.fromName,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.senderPublicKey = '',
  });

  factory IncomingTransferRequest.fromJson(Map<String, dynamic> json) =>
      IncomingTransferRequest(
        transferId: (json['transferId'] as String?) ?? '',
        from: (json['from'] as String?) ?? '',
        fromName: (json['fromName'] as String?) ?? 'Otro dispositivo',
        fileName: (json['fileName'] as String?) ?? '',
        fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
        mimeType: (json['mimeType'] as String?) ?? 'application/octet-stream',
        senderPublicKey: ((json['e2e'] as Map?)?['publicKey'] as String?) ?? '',
      );
}
