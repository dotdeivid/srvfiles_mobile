import 'dart:typed_data';

/// Buffer that accumulates incoming binary chunks during a P2P file transfer.
///
/// Created when this device accepts an incoming transfer request. Each binary
/// chunk from the sender is appended to [chunks] and [received] is incremented
/// by the chunk size. When `received >= total` the transfer is complete and the
/// caller assembles the final file from [chunks].
class ReceiveBuffer {
  final List<Uint8List> chunks;
  int received;
  final int total;
  final String fileName;
  final String mimeType;

  ReceiveBuffer({
    required this.chunks,
    required this.received,
    required this.total,
    required this.fileName,
    required this.mimeType,
  });
}
