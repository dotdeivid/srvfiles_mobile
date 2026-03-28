import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

const String _storageKey = 'srvfiles-device-name';

/// Mismos adjetivos y animales que el frontend web (useDeviceName.ts).
const List<String> _adjectives = [
  'Rápido', 'Azul', 'Verde', 'Veloz',
  'Brillante', 'Tranquilo', 'Creativo', 'Curioso',
];

const List<String> _animals = [
  'Zorro', 'Puma', 'Delfín', 'Águila',
  'Jaguar', 'Lobo', 'Oso', 'Cóndor',
];

/// Genera un nombre aleatorio tipo "Rápido Zorro".
String _randomName() {
  final rng = Random();
  final adj = _adjectives[rng.nextInt(_adjectives.length)];
  final animal = _animals[rng.nextInt(_animals.length)];
  return '$adj $animal';
}

class DeviceNameService {
  /// Obtiene el nombre guardado, o genera uno aleatorio si es la primera vez.
  Future<String> getName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_storageKey) ?? _randomName();
      AppLogger.instance.debug('[DeviceNameService] getName: $name');
      return name;
    } catch (e) {
      AppLogger.instance.error('[DeviceNameService] getName failed', error: e);
      return _randomName();
    }
  }

  /// Guarda el nombre. Si está vacío, genera uno aleatorio.
  Future<String> saveName(String name) async {
    try {
      final trimmed = name.trim();
      final finalName = trimmed.isEmpty ? _randomName() : trimmed;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, finalName);
      AppLogger.instance.info('[DeviceNameService] name saved: $finalName');
      return finalName;
    } catch (e) {
      AppLogger.instance.error('[DeviceNameService] saveName failed', error: e);
      rethrow;
    }
  }

  /// Devuelve true si es la primera vez que se abre la app (no hay nombre guardado).
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_storageKey);
  }

  /// Genera un nombre aleatorio sin guardarlo.
  String generateRandomName() => _randomName();
}
