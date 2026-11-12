/// Puerto por defecto del backend SrvFiles (desktop) y del relay embebido.
const int defaultServerPort = 3001;

/// Configuración de conexión al backend de SrvFiles.
/// La URL base se establece dinámicamente vía discovery o ingreso manual.
class ApiConfig {
  final String baseUrl;

  ApiConfig(this.baseUrl);

  String get filesUrl => '$baseUrl/api/files';
  String get uploadUrl => '$baseUrl/api/files/upload';
  String get statsUrl => '$baseUrl/api/files/stats';
  String get configUrl => '$baseUrl/api/config';
  String get healthUrl => '$baseUrl/api/health';
  String get authUrl => '$baseUrl/api/auth';

  /// URL de WebSocket para P2P (reemplaza http→ws).
  String get wsUrl => '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/ws';

  /// URL de descarga para un archivo específico.
  String downloadUrl(String filename) =>
      '$baseUrl/api/files/download/${Uri.encodeComponent(filename)}';
}
