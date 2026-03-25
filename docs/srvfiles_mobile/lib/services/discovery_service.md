# services/discovery_service.dart

**Archivo:** `lib/services/discovery_service.dart`
**Rol:** Escanea la subnet local en busca de instancias de SrvFiles. Equivalente al `discovery.service.ts` del backend, pero ejecutándose en el dispositivo móvil.

---

## Clase `DiscoveredServer`

```dart
class DiscoveredServer {
  final String ip;
  final String url;
  final String appName;
}
```

El resultado de encontrar un servidor. Mismo formato que el backend devuelve en `/api/discovery`.

---

## Función `probe`

```dart
Future<DiscoveredServer?> probe(String ip) async {
  try {
    final url = 'http://$ip:3001/api/health';
    final response = await http.get(Uri.parse(url))
        .timeout(const Duration(milliseconds: 500));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['status'] == 'ok' && json['app'] == 'SrvFiles') {
        return DiscoveredServer(
          ip: ip,
          url: 'http://$ip:3001',
          appName: json['appName'] ?? 'SrvFiles',
        );
      }
    }
  } catch (_) {}
  return null;
}
```

Intenta conectar al endpoint `/api/health` de una IP específica con un timeout de 500ms. Si responde correctamente, retorna el servidor encontrado. Si no responde o da error, retorna `null` silenciosamente (el `catch (_)` descarta cualquier excepción).

El patrón es idéntico al `probeHost()` del backend: 500ms de timeout, nunca rechaza la promesa/Future.

---

## Función `tryConnect`

```dart
Future<DiscoveredServer?> tryConnect(String url) async {
  // Extrae la IP de la URL y la prueba directamente
}
```

Variante de `probe` que acepta una URL completa en lugar de una IP. Usada en `SplashScreen` para verificar el último servidor conocido antes de hacer el escaneo completo.

---

## Función `scanLan`

```dart
Future<List<DiscoveredServer>> scanLan() async {
  final localIp = await _getLocalIp();
  if (localIp == null) return [];

  final parts = localIp.split('.');
  final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
  final ips = List.generate(254, (i) => '$subnet.${i + 1}');

  final results = await Future.wait(ips.map(probe));
  return results.whereType<DiscoveredServer>().toList();
}
```

### `Future.wait`

Lanza las 254 peticiones simultáneamente, igual que `Promise.all` en JavaScript. El tiempo total es el de la petición más lenta (~500ms), no la suma (127 segundos si fuera secuencial).

### `.whereType<DiscoveredServer>()`

Filtra los `null` del array de resultados y convierte el tipo a `List<DiscoveredServer>`. Es más idiomático que `.where((r) => r != null).cast<DiscoveredServer>()`.

---

## Función `_getLocalIp`

```dart
Future<String?> _getLocalIp() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }
  return null;
}
```

Obtiene la IP local del dispositivo usando la API de red de Dart (`dart:io`). Itera por las interfaces de red, descarta las de loopback (`127.0.0.1`), y retorna la primera IP LAN que encuentra.
