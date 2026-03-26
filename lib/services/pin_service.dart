import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestiona el PIN de seguridad del modo servidor.
/// El PIN siempre es obligatorio — se genera automáticamente al encender el servidor.
class PinService {
  static const _hashKey = 'security_pin_hash';

  /// Genera un PIN numérico de 6 dígitos, guarda su SHA-256 en SharedPreferences
  /// y retorna el PIN en texto plano (para mostrarlo en la UI una sola vez).
  Future<String> generatePin() async {
    final rng = Random.secure();
    final pin = (rng.nextInt(900000) + 100000).toString(); // 100000–999999
    final hash = sha256.convert(utf8.encode(pin)).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey, hash);
    return pin;
  }

  /// Verifica si el PIN ingresado es correcto comparando su SHA-256 con el almacenado.
  Future<bool> validatePin(String input) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_hashKey);
    if (stored == null) return false;
    final inputHash = sha256.convert(utf8.encode(input)).toString();
    return inputHash == stored;
  }

  /// Elimina el hash del PIN de SharedPreferences al apagar el servidor.
  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
  }
}
