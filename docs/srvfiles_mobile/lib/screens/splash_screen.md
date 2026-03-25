# screens/splash_screen.dart

**Archivo:** `lib/screens/splash_screen.dart`
**Rol:** Pantalla inicial. Escanea la red local, muestra los servidores encontrados, y permite conectar manualmente o continuar sin servidor.

---

## Estructura del widget

```
SplashScreen (StatefulWidget)
└── _SplashScreenState
    ├── _scan()             — escanea la red
    ├── _saveLastServer()   — persiste la URL del servidor
    ├── _ensureDeviceName() — pide nombre si es primer lanzamiento
    ├── _onServerSelected() — navega al HomeScreen con servidor
    ├── _onSkipServer()     — navega al HomeScreen sin servidor
    ├── _connectManual()    — conecta desde input manual
    └── _buildServerList()  — construye la lista de resultados
```

---

## Estado

```dart
bool _scanning = true;
List<DiscoveredServer> _servers = [];
final _manualController = TextEditingController();
```

---

## Método `_scan`

```dart
Future<void> _scan() async {
  setState(() { _scanning = true; _servers = []; });

  // Primero: probar el último servidor conocido
  final lastUrl = prefs.getString('last_server');
  if (lastUrl != null) {
    final server = await DiscoveryService().tryConnect(lastUrl);
    if (server != null && mounted) {
      _onServerSelected(server.url);
      return; // Auto-connect exitoso
    }
  }

  // Si no hay último servidor o no responde: escanear la red
  final results = await DiscoveryService().scanLan();
  if (mounted) {
    setState(() { _servers = results; _scanning = false; });
  }
}
```

### Estrategia de dos pasos

1. **Reconexión rápida**: si el usuario usó un servidor antes, intenta conectar directamente a él. Si responde, navega sin mostrar la pantalla de selección.
2. **Descubrimiento**: si no hay servidor previo, o si ya no responde, escanea toda la subnet.

Esto hace que la experiencia sea fluida: en el uso cotidiano (mismo servidor de siempre), la app conecta automáticamente en ~500ms.

---

## Método `_saveLastServer`

```dart
Future<void> _saveLastServer(String url) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('last_server', url);
}
```

Persiste la URL del servidor seleccionado para la próxima vez que la app se abra.

---

## Método `_ensureDeviceName`

```dart
Future<void> _ensureDeviceName() async {
  final isFirst = await DeviceNameService().isFirstLaunch();
  if (!isFirst || !mounted) return;

  final defaultName = DeviceNameService().generateRandomName();
  final chosen = await NameDialog.show(context, defaultName);
  if (chosen != null && chosen.trim().isNotEmpty) {
    await DeviceNameService().saveName(chosen.trim());
  } else {
    await DeviceNameService().saveName(defaultName);
  }
}
```

En el primer lanzamiento, muestra el `NameDialog` antes de continuar. Si el usuario omite el diálogo, guarda el nombre aleatorio generado. Esto garantiza que siempre haya un nombre disponible para el protocolo WebSocket.

---

## Método `_onServerSelected`

```dart
Future<void> _onServerSelected(String url) async {
  await _ensureDeviceName();
  await _saveLastServer(url);
  if (!mounted) return;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => HomeScreen(serverUrl: url)),
  );
}
```

`pushReplacement` reemplaza la pantalla actual en la pila de navegación en lugar de apilarla encima. Esto hace que el botón "atrás" del sistema operativo no vuelva a la `SplashScreen`.

---

## Método `_onSkipServer`

```dart
Future<void> _onSkipServer() async {
  await _ensureDeviceName();
  if (!mounted) return;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const HomeScreen()),
  );
}
```

Navega al `HomeScreen` sin `serverUrl`. En ese modo, la app solo hace P2P con el relay embebido.

---

## Método `_connectManual`

```dart
void _connectManual() {
  String url = _manualController.text.trim();
  if (url.isEmpty) return;
  if (!url.startsWith('http')) url = 'http://$url';
  if (!RegExp(r':\d+$').hasMatch(url)) url = '$url:3001';
  _onServerSelected(url);
}
```

Normaliza la entrada del usuario: agrega `http://` si falta, y agrega `:3001` si no hay puerto explícito. El regex `:\d+$` verifica que el string termine con dos puntos y uno o más dígitos.

---

## Widget `_ServerRow`

```dart
class _ServerRow extends StatelessWidget {
  // Muestra un servidor descubierto con nombre, IP y botón "Conectar"
}
```

Widget privado (con prefijo `_`) que renderiza cada servidor en la lista. No tiene acceso directo a `_SplashScreenState`; recibe la acción de conexión como callback.
