import '../../services/received_files_service.dart';
import '../../services/transfer_service.dart';

/// Estado de una recepción P2P en curso.
///
/// Los chunks se escriben directo a disco ([sink], un archivo `.part`) en vez
/// de acumularse en memoria. Al llegar `send-complete` se comprueba que
/// [received] coincida con [total] antes de guardar el archivo.
class ReceiveBuffer {
  final ReceivedFileSink sink;

  /// Conexión por la que llega la transferencia (principal o del pool).
  final TransferService service;
  int received;
  final int total;
  final String fileName;
  final String mimeType;
  final String peerName;

  ReceiveBuffer({
    required this.sink,
    required this.service,
    required this.total,
    required this.fileName,
    required this.mimeType,
    required this.peerName,
    this.received = 0,
  });
}
