import 'dart:io';
import '../../services/e2e_service.dart';
import '../../services/transfer_service.dart';

/// Holds the state of a file send that is waiting for the peer to accept.
///
/// Created when the user picks a file and sends a transfer offer with this
/// side's E2E public key. When the receiver's key arrives (`send-key`) the
/// [session] is derived; once the peer accepts, the controller streams the
/// file through the [service]. [cancelToken] stops the send loop.
class PendingSend {
  final String transferId;
  final File file;
  final String fileName;
  final String peerId;

  /// The transfer service instance through which to send chunks.
  /// May be the main connection or a pool connection (direct mode).
  final TransferService service;

  final CancelToken cancelToken;

  /// Claves E2E propias de esta transferencia.
  final E2EKeyPair keyPair;

  /// Sesión E2E; null hasta que llega la clave del receptor.
  E2ESession? session;

  PendingSend({
    required this.transferId,
    required this.file,
    required this.fileName,
    required this.peerId,
    required this.service,
    required this.keyPair,
    CancelToken? cancelToken,
  }) : cancelToken = cancelToken ?? CancelToken();
}
