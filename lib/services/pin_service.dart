import 'dart:math';
import 'app_logger.dart';

/// Gestiona el PIN de seguridad del modo servidor.
/// El PIN siempre es obligatorio — se genera automáticamente al encender el servidor.
///
/// Vive solo en memoria: guardar el hash de un PIN de 6 dígitos no protege
/// nada (son un millón de combinaciones) y el PIN deja de valer al apagar el
/// servidor.
class PinService {
  String? _pin;

  /// PIN actual, o null si el modo servidor está apagado.
  String? get currentPin => _pin;

  /// Genera un PIN numérico de 6 dígitos y lo devuelve.
  String generatePin() {
    final rng = Random.secure();
    _pin = (rng.nextInt(900000) + 100000).toString(); // 100000–999999
    AppLogger.instance.info('[PinService] PIN generated');
    return _pin!;
  }

  /// Verifica si el PIN ingresado es correcto (comparación en tiempo constante).
  bool validatePin(String input) {
    final pin = _pin;
    if (pin == null) {
      AppLogger.instance.warn('[PinService] validatePin: no PIN active');
      return false;
    }
    var diff = input.length ^ pin.length;
    for (var i = 0; i < pin.length; i++) {
      final c = i < input.length ? input.codeUnitAt(i) : 0;
      diff |= c ^ pin.codeUnitAt(i);
    }
    final valid = diff == 0;
    if (!valid) AppLogger.instance.warn('[PinService] validatePin: wrong PIN submitted');
    return valid;
  }

  /// Invalida el PIN al apagar el servidor.
  void clearPin() {
    _pin = null;
    AppLogger.instance.info('[PinService] PIN cleared');
  }
}
