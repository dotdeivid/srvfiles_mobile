class IncomingTransferRequest {
  final String transferId;
  final String from;
  final String fromName;
  final String fileName;
  final int fileSize;
  final String mimeType;

  const IncomingTransferRequest({
    required this.transferId,
    required this.from,
    required this.fromName,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });

  factory IncomingTransferRequest.fromJson(Map<String, dynamic> json) =>
      IncomingTransferRequest(
        transferId: json['transferId'] as String,
        from: json['from'] as String,
        fromName: json['fromName'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int,
        mimeType: json['mimeType'] as String,
      );
}
