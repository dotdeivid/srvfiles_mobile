import 'dart:io';
import '../crypto_service.dart';

/// A connected WebSocket client tracked by the relay.
class ConnectedClient {
  final WebSocket ws;
  final String clientId;
  String appName;
  bool receiving;
  final String ip;
  final String deviceType;

  /// true if the client connected from localhost (owner of this relay).
  final bool isOwner;

  /// Session cipher — null if the client did not perform key exchange.
  SessionCipher? cipher;

  /// Soporta cifrado de extremo a extremo (anunciado en hello con e2e: 1).
  bool e2e;

  ConnectedClient({
    required this.ws,
    required this.clientId,
    required this.appName,
    required this.receiving,
    required this.ip,
    required this.deviceType,
    this.isOwner = false,
    this.cipher,
    this.e2e = false,
  });
}

/// Tracks an active file transfer between two connected clients.
class TransferSession {
  final String transferId;
  final String senderClientId;
  final String receiverClientId;
  final String fileName;
  final int fileSize;
  final String mimeType;

  /// true cuando el receptor aceptó; antes de eso no se reenvían chunks.
  bool accepted = false;

  /// true cuando el receptor ya mandó su clave pública E2E.
  bool keySent = false;

  TransferSession({
    required this.transferId,
    required this.senderClientId,
    required this.receiverClientId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

/// Rate-limiting entry for authentication attempts per IP.
class RateEntry {
  int count;
  DateTime blockedUntil;

  RateEntry({required this.count, required this.blockedUntil});
}
