import '../config/api_config.dart';

/// Normaliza lo que el usuario escribe como dirección de servidor.
///
/// Acepta `192.168.1.5`, `192.168.1.5:3001`, `http://192.168.1.5/`,
/// `http://host:3001/ruta` y devuelve `http://host:puerto` sin barra final.
/// Devuelve null si no se puede interpretar como URL.
String? normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final port = uri.hasPort ? uri.port : defaultServerPort;
  return '${uri.scheme}://${uri.host}:$port';
}

/// true si las dos URLs apuntan al mismo host (sin comparar por subcadena).
bool sameHost(String? a, String? b) {
  if (a == null || b == null) return false;
  final ua = Uri.tryParse(a);
  final ub = Uri.tryParse(b);
  if (ua == null || ub == null) return false;
  return ua.host == ub.host;
}
