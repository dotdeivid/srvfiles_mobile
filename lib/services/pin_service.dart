import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

/// Gestiona el PIN de seguridad del modo servidor.
/// El PIN siempre es obligatorio — se genera automáticamente al encender el servidor.
class PinService {
  static const _hashKey = 'security_pin_hash';

  /// Genera un PIN numérico de 6 dígitos, guarda su SHA-256 en SharedPreferences
  /// y retorna el PIN en texto plano (para mostrarlo en la UI una sola vez).
  Future<String> generatePin() async {
    try {
      final rng = Random.secure();
      final pin = (rng.nextInt(900000) + 100000).toString(); // 100000–999999
      final hash = sha256.convert(utf8.encode(pin)).toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hashKey, hash);
      AppLogger.instance.info('[PinService] PIN generated and stored');
      return pin;
    } catch (e) {
      AppLogger.instance.error('[PinService] generatePin failed', error: e);
      rethrow;
    }
  }

  /// Verifica si el PIN ingresado es correcto comparando su SHA-256 con el almacenado.
  Future<bool> validatePin(String input) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_hashKey);
      if (stored == null) {
        AppLogger.instance.warn('[PinService] validatePin: no PIN hash stored');
        return false;
      }
      final inputHash = sha256.convert(utf8.encode(input)).toString();
      final valid = inputHash == stored;
      if (!valid) AppLogger.instance.warn('[PinService] validatePin: wrong PIN submitted');
      return valid;
    } catch (e) {
      AppLogger.instance.error('[PinService] validatePin failed', error: e);
      return false;
    }
  }

  /// Elimina el hash del PIN de SharedPreferences al apagar el servidor.
  Future<void> clearPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_hashKey);
      AppLogger.instance.info('[PinService] PIN cleared');
    } catch (e) {
      AppLogger.instance.error('[PinService] clearPin failed', error: e);
    }
  }
}
