import 'package:shared_preferences/shared_preferences.dart';

const String _lastServerKey = 'srvfiles-last-server';

/// Último servidor al que se conectó el usuario (para probarlo primero en el
/// splash).
class ServerHistory {
  const ServerHistory();

  Future<String?> getLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastServerKey);
  }

  Future<void> saveLastServer(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastServerKey, url);
  }
}
