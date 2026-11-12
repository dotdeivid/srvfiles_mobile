/// Qué páginas de navegador pueden usar la API y el WebSocket del relay.
/// Misma regla que el backend Go (`internal/webguard`).
///
/// Sin esto, cualquier web abierta en el navegador del teléfono (u otro
/// equipo) podría conectarse al relay y ver la lista de dispositivos.
///
/// Se permiten:
/// - peticiones sin `Origin` (apps nativas: la app móvil, curl);
/// - la propia página servida por el relay (`Origin` host == `Host`);
/// - la app de escritorio (`tauri://localhost`, `http(s)://tauri.localhost`);
/// - Vite en desarrollo (`localhost:5173`).
bool isAllowedOrigin(String? origin, String? host) {
  if (origin == null || origin.isEmpty) return true;
  final Uri u;
  try {
    u = Uri.parse(origin);
  } catch (_) {
    return false;
  }
  if (u.host.isEmpty) return false;
  final authority = u.hasPort ? '${u.host}:${u.port}' : u.host;
  switch ('${u.scheme}://$authority') {
    case 'tauri://localhost' || 'http://tauri.localhost' || 'https://tauri.localhost':
      return true;
  }
  if (host != null && authority == host.toLowerCase()) return true;
  return (u.host == 'localhost' || u.host == '127.0.0.1') && u.hasPort && u.port == 5173;
}
