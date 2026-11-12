/// Representa una transferencia P2P activa (enviando o recibiendo).
/// Replica ActiveTransfer de useTransfer.ts del frontend web.
class ActiveTransfer {
  final String transferId;
  final String fileName;
  final int fileSize;
  final int progress; // 0-100
  final TransferDirection direction;
  final String peerName;
  final String peerId;
  final bool waiting; // true mientras el sender espera accept/reject

  /// Código de verificación E2E (6 dígitos); el emisor lo ve al llegar la
  /// clave del receptor y debe coincidir con el que ve el receptor.
  final String? sas;

  const ActiveTransfer({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.progress,
    required this.direction,
    required this.peerName,
    required this.peerId,
    required this.waiting,
    this.sas,
  });

  ActiveTransfer copyWith({
    int? progress,
    bool? waiting,
    String? sas,
  }) {
    return ActiveTransfer(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      progress: progress ?? this.progress,
      direction: direction,
      peerName: peerName,
      peerId: peerId,
      waiting: waiting ?? this.waiting,
      sas: sas ?? this.sas,
    );
  }
}

enum TransferDirection { sending, receiving }
