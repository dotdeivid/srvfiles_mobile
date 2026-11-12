import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

/// Resultado de un intento de login con PIN.
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  final String token;
  const AuthSuccess(this.token);
}

class AuthFailure extends AuthResult {
  /// Mensaje listo para mostrar en el diálogo de PIN.
  final String message;
  const AuthFailure(this.message);
}

/// Autenticación con PIN contra un servidor SrvFiles y persistencia del token
/// por servidor, para no pedir el PIN en cada conexión.
class AuthService {
  const AuthService();

  static const _tokensKey = 'srvfiles-session-tokens';
  static const _timeout = Duration(seconds: 10);

  /// Envía el PIN a `POST /api/auth` y devuelve el token o un error legible.
  Future<AuthResult> login(String baseUrl, String pin) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}),
          )
          .timeout(_timeout);
      switch (response.statusCode) {
        case 200:
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final token = data['token'] as String?;
          if (token == null || token.isEmpty) {
            return const AuthFailure('Respuesta inválida del servidor');
          }
          await saveToken(baseUrl, token);
          return AuthSuccess(token);
        case 401:
          return const AuthFailure('PIN incorrecto');
        case 429:
          return const AuthFailure('Demasiados intentos. Esperá un minuto y probá de nuevo.');
        default:
          return AuthFailure('El servidor respondió con un error (${response.statusCode})');
      }
    } catch (e) {
      AppLogger.instance.warn('[AuthService] login error: $e');
      return const AuthFailure('No se pudo contactar al servidor');
    }
  }

  /// Token guardado para [baseUrl], o null.
  Future<String?> getSavedToken(String baseUrl) async {
    final tokens = await _load();
    return tokens[baseUrl];
  }

  Future<void> saveToken(String baseUrl, String token) async {
    final tokens = await _load();
    tokens[baseUrl] = token;
    await _store(tokens);
  }

  /// Olvida el token de [baseUrl] (rechazado por el servidor).
  Future<void> clearToken(String baseUrl) async {
    final tokens = await _load();
    if (tokens.remove(baseUrl) != null) await _store(tokens);
  }

  Future<Map<String, String>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tokensKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _store(Map<String, String> tokens) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokensKey, jsonEncode(tokens));
    } catch (e) {
      AppLogger.instance.warn('[AuthService] could not persist token: $e');
    }
  }
}
