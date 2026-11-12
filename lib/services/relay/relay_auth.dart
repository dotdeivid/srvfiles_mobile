import 'dart:convert';
import 'dart:io';
import '../pin_service.dart';
import 'relay_types.dart';

/// Handles authentication, rate limiting, and session token management
/// for the embedded relay server.
class RelayAuth {
  PinService? pinService;

  /// Active session tokens: token → expiry. Se renuevan con cada uso.
  final Map<String, DateTime> _sessions = {};

  /// Rate limiting: IP → RateEntry
  final Map<String, RateEntry> rateLimits = {};

  /// Fallos recientes de todas las IPs (límite global).
  final List<DateTime> _globalFailures = [];
  DateTime _globalBlockedUntil = DateTime(0);

  static const maxAttempts = 5;
  static const blockDuration = Duration(minutes: 1);
  static const maxGlobalFailures = 20;
  static const globalWindow = Duration(minutes: 1);
  static const sessionTtl = Duration(hours: 12);

  /// PIN actual (en memoria, nunca se persiste).
  String? get currentPin => pinService?.currentPin;

  /// true si [token] corresponde a una sesión vigente. Renueva su vencimiento.
  bool isValidToken(String token) {
    if (token.isEmpty) return false;
    final expiry = _sessions[token];
    if (expiry == null) return false;
    final now = DateTime.now();
    if (expiry.isBefore(now)) {
      _sessions.remove(token);
      return false;
    }
    _sessions[token] = now.add(sessionTtl);
    return true;
  }

  /// Registra [token] como sesión válida y lo devuelve.
  String createSession(String token) {
    _sessions[token] = DateTime.now().add(sessionTtl);
    return token;
  }

  /// Check if a request has a valid session token (header only: el token de
  /// sesión nunca se acepta en la URL).
  bool isAuthorized(HttpRequest req) =>
      isValidToken(req.headers.value('x-srvfiles-token') ?? '');

  // ─── Link tokens (descargas y vistas previas) ─────────────────────

  static const linkTokenTtl = Duration(minutes: 10);
  final Map<String, ({String fileName, DateTime expiry})> _linkTokens = {};

  /// Token para URLs (<a>, <img>, <video>) que autoriza solo [fileName] por
  /// unos minutos. Se puede usar varias veces (el video pide rangos).
  String createLinkToken(String fileName, String token) {
    final now = DateTime.now();
    _linkTokens.removeWhere((_, v) => v.expiry.isBefore(now));
    _linkTokens[token] = (fileName: fileName, expiry: now.add(linkTokenTtl));
    return token;
  }

  bool isValidLinkToken(String token, String fileName) {
    final entry = _linkTokens[token];
    if (entry == null) return false;
    if (entry.expiry.isBefore(DateTime.now())) {
      _linkTokens.remove(token);
      return false;
    }
    return entry.fileName == fileName;
  }

  /// Handle POST /api/auth — validate PIN, issue session token.
  Future<void> handleAuth(HttpRequest req, String Function() generateUuid) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '';
    final now = DateTime.now();

    // Rate limiting (por IP y global)
    final entry = rateLimits[ip];
    if (_globalBlockedUntil.isAfter(now) ||
        (entry != null && entry.blockedUntil.isAfter(now))) {
      _json(req, HttpStatus.tooManyRequests,
          {'error': 'Demasiados intentos. Intentá en 60 segundos.'});
      return;
    }

    Map<String, dynamic> body;
    try {
      final raw = await utf8.decodeStream(req).timeout(const Duration(seconds: 10));
      if (raw.length > 1024) throw const FormatException('body too large');
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _json(req, HttpStatus.badRequest, {'error': 'Body JSON inválido'});
      return;
    }

    final pin = body['pin'] is String ? body['pin'] as String : '';
    final valid = pinService?.validatePin(pin) ?? false;

    if (valid) {
      rateLimits.remove(ip);
      final token = generateUuid();
      _sessions[token] = now.add(sessionTtl);
      _json(req, HttpStatus.ok, {'token': token});
    } else {
      final current = rateLimits[ip] ?? RateEntry(count: 0, blockedUntil: DateTime(0));
      current.count++;
      if (current.count >= maxAttempts) {
        current.blockedUntil = now.add(blockDuration);
        current.count = 0;
      }
      rateLimits[ip] = current;

      _globalFailures
        ..add(now)
        ..removeWhere((t) => now.difference(t) > globalWindow);
      if (_globalFailures.length >= maxGlobalFailures) {
        _globalBlockedUntil = now.add(blockDuration);
        _globalFailures.clear();
      }
      _json(req, HttpStatus.unauthorized, {'error': 'PIN incorrecto'});
    }
  }

  /// Clear all state (for server mode stop).
  void clear() {
    _sessions.clear();
    _linkTokens.clear();
    rateLimits.clear();
    _globalFailures.clear();
    _globalBlockedUntil = DateTime(0);
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }
}
