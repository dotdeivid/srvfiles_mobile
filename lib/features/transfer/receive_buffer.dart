import '../../services/e2e_service.dart';
import '../../services/received_files_service.dart';
import '../../services/transfer_service.dart';

/// Estado de una recepción P2P en curso.
///
/// Cada chunk se descifra con su índice ([session]) y se escribe directo a
/// disco ([sink], un archivo `.part`). Las operaciones se encadenan en [work]
/// para conservar el orden. Al llegar `send-complete` se verifica el marcador
/// final cifrado (cantidad de chunks, tamaño y nombre).
class ReceiveBuffer {
  final ReceivedFileSink sink;

  /// Conexión por la que llega la transferencia (principal o del pool).
  final TransferService service;
  final E2ESession session;

  /// Índice del próximo chunk esperado (= chunks recibidos).
  int nextIndex = 0;
  int received;
  final int total;
  final String fileName;
  final String mimeType;
  final String peerName;

  /// Cadena de descifrado + escritura (en orden de llegada).
  Future<void> work = Future.value();

  /// Motivo de fallo, si lo hubo.
  String? failed;

  ReceiveBuffer({
    required this.sink,
    required this.service,
    required this.session,
    required this.total,
    required this.fileName,
    required this.mimeType,
    required this.peerName,
    this.received = 0,
  });
}
