import 'dart:io';
import '../../services/transfer_service.dart';

/// Holds the state of a file send that is waiting for the peer to accept.
///
/// Created when the user picks a file and sends a transfer offer. Once the
/// peer accepts (via `send-accept` WS message), the controller reads the
/// file and starts streaming chunks through the [service].
class PendingSend {
  final String transferId;
  final File file;
  final String peerId;

  /// The transfer service instance through which to send chunks.
  /// May be the main connection or a pool connection (direct mode).
  final TransferService service;

  const PendingSend({
    required this.transferId,
    required this.file,
    required this.peerId,
    required this.service,
  });
}
