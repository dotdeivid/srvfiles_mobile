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

  const ActiveTransfer({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.progress,
    required this.direction,
    required this.peerName,
    required this.peerId,
    required this.waiting,
  });

  ActiveTransfer copyWith({
    int? progress,
    bool? waiting,
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
    );
  }
}

enum TransferDirection { sending, receiving }
