import 'dart:convert';
import 'dart:io';
import '../pin_service.dart';
import 'relay_types.dart';

/// Handles authentication, rate limiting, and session token management
/// for the embedded relay server.
class RelayAuth {
  PinService? pinService;
  String? currentPin;

  /// Active session tokens: token → true.
  final Map<String, bool> sessions = {};

  /// Rate limiting: IP → RateEntry
  final Map<String, RateEntry> rateLimits = {};

  static const maxAttempts = 5;
  static const blockDuration = Duration(minutes: 1);

  /// Check if a request has a valid session token.
  bool isAuthorized(HttpRequest req) {
    final token = req.headers.value('x-srvfiles-token')
        ?? req.uri.queryParameters['token']
        ?? '';
    return sessions[token] == true;
  }

  /// Handle POST /api/auth — validate PIN, issue session token.
  Future<void> handleAuth(HttpRequest req, String Function() generateUuid) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '';

    // Rate limiting
    final entry = rateLimits[ip];
    if (entry != null && entry.blockedUntil.isAfter(DateTime.now())) {
      req.response
        ..statusCode = HttpStatus.tooManyRequests
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Demasiados intentos. Intentá en 60 segundos.'}))
        ..close();
      return;
    }

    Map<String, dynamic> body;
    try {
      final raw = await utf8.decodeStream(req);
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Body JSON inválido'}))
        ..close();
      return;
    }

    final pin = body['pin'] as String? ?? '';
    final valid = await pinService!.validatePin(pin);

    if (valid) {
      rateLimits.remove(ip);
      final token = generateUuid();
      sessions[token] = true;
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'token': token}))
        ..close();
    } else {
      final current = rateLimits[ip] ?? RateEntry(count: 0, blockedUntil: DateTime(0));
      current.count++;
      if (current.count >= maxAttempts) {
        current.blockedUntil = DateTime.now().add(blockDuration);
      }
      rateLimits[ip] = current;
      req.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'PIN incorrecto'}))
        ..close();
    }
  }

  /// Handle GET /api/pin
  void handlePin(HttpRequest req) {
    if (currentPin == null) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'No server mode active'}))
        ..close();
      return;
    }
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'pin': currentPin}))
      ..close();
  }

  /// Clear all state (for server mode stop).
  void clear() {
    sessions.clear();
    rateLimits.clear();
    currentPin = null;
  }
}
