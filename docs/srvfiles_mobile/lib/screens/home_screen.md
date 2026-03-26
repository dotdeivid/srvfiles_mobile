# screens/home_screen.dart

**Archivo:** `lib/screens/home_screen.dart`
**Rol:** Pantalla principal de la app. Gestiona archivos del servidor, transferencias P2P, archivos recibidos, autenticación PIN, server mode, y el relay embebido.

---

## Widget `HomeScreen`

```dart
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.serverUrl, this.autoServerMode = false});

  final String? serverUrl;       // null = modo relay sin servidor externo
  final bool autoServerMode;     // true = activar server mode automáticamente al iniciar
}
```

---

## Getters de estado de servidor

```dart
bool get _hasServer => widget.serverUrl != null;
bool get _isServer => _hasServer || _relay.isServerMode;
```

- `_hasServer`: conectado a un servidor externo.
- `_isServer`: hay archivos que gestionar — sea porque hay servidor externo o porque el relay propio está en server mode. Controla si se muestran la lista de archivos, el FAB, la barra de disco, y el QR.

---

## Estado relevante

```dart
FilesService? _filesService;
ApiConfig? _apiConfig;
List<FileInfo> _files = [];
DiskStats? _stats;
AppConfig? _config;
bool _loading = true;
String? _error;
bool _connectionLost = false;

TransferService _transferService = TransferService();
EmbeddedRelay _relay = EmbeddedRelay();
List<TransferClient> _onlineClients = [];
String? _myClientId;
ActiveTransfer? _activeTransfer;
```

No hay polling. Los datos se actualizan solo después de operaciones explícitas (subida, eliminación) o al reconectar el WebSocket.

---

## `initState`

```dart
@override
void initState() {
  super.initState();
  if (_hasServer) {
    _apiConfig = ApiConfig(widget.serverUrl!);
    _filesService = FilesService(_apiConfig!);
    _initTransfer();   // _initialLoad() se llama desde onAuthOk tras autenticar
  } else {
    _loading = false;
    _startRelay();
  }
  _loadReceivedFiles();
}
```

Para servidores externos, **no se llama `_initialLoad()` en initState**. La carga ocurre desde `onAuthOk` después de completar la autenticación. Esto evita que aparezca el botón "Reintentar" mientras el modal de PIN está abierto.

---

## Ciclo de vida del foreground service — `didChangeAppLifecycleState`

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // Volvió a primer plano: quitar notificación de background
    _notificationService.stopForeground();
    if (_apiConfig != null && !_transferService.isConnected) {
      _connectWebSocket();
    }
  } else if (state == AppLifecycleState.paused) {
    // Se fue a segundo plano: activar foreground service para mantener WS vivo
    _notificationService.startForeground();
  }
}
```

El foreground service (notificación persistente de Android) **solo está activo mientras la app está en segundo plano**:

- Al pasar a `paused` (app se minimiza o pantalla se bloquea): se activa con `startForeground()`.
- Al volver a `resumed` (usuario vuelve a la app): se desactiva con `stopForeground()`.
- Al destruir la pantalla (`dispose`): también se llama `stopForeground()` para limpiar.

Esto evita que aparezca la notificación mientras el usuario está usando la app activamente.

---

## Método `_startRelay`

```dart
Future<void> _startRelay() async {
  await _relay.start();
  _apiConfig = ApiConfig(_relay.url!);
  _initTransfer();
  if (widget.autoServerMode) _activateServerMode();
}
```

Levanta el relay embebido y conecta el WebSocket al relay propio. El foreground service **no se activa aquí** — se activa dinámicamente según el ciclo de vida de la app (ver `didChangeAppLifecycleState`).

---

## Método `_activateServerMode`

```dart
Future<void> _activateServerMode() async {
  // Mostrar advertencia (primera vez)
  if (!dismissed) {
    final confirmed = await ServerModeWarningDialog.show(context);
    if (confirmed != true) return;
  }

  final pin = await _relay.startServerMode();

  // Auto-autenticarse con el relay local
  final response = await http.post(
    Uri.parse('http://127.0.0.1:${_relay.port}/api/auth'),
    body: jsonEncode({'pin': pin}),
  );
  final token = jsonDecode(response.body)['token'] as String;
  _transferService.setToken(token);

  // Configurar FilesService apuntando al relay local
  final localConfig = ApiConfig('http://127.0.0.1:${_relay.port}');
  _filesService = FilesService(localConfig)..setToken(token);

  _connectWebSocket();
  await _initialLoad();
}
```

Activa el servidor, obtiene el token auto-autenticándose por loopback, configura el `FilesService` local, y carga los archivos.

---

## Método `_showPinEntryDialog`

```dart
Future<void> _showPinEntryDialog({String? errorMessage}) async {
  final pin = await PinEntryDialog.show(context, error: errorMessage);
  if (!mounted) return;
  if (pin == null) {
    // Usuario canceló → volver al splash
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
    return;
  }
  // Autenticar con el servidor externo...
}
```

Si el usuario cancela el modal de PIN, **navega de vuelta al splash** en lugar de quedar en una pantalla con error.

---

## Método `_connectWebSocket`

```dart
Future<void> _connectWebSocket() async {
  _transferService.onAuthOk = () async {
    await _ensureDeviceName();
    _transferService.register(_deviceName);
    _transferService.setReceiving(true);
    if (_hasServer) _initialLoad();   // ← carga inicial después de auth
  };
  _transferService.connect(_apiConfig!);
}
```

El callback `onAuthOk` es el punto de entrada para la carga inicial en servidores externos. Para el relay propio se llama directamente desde `_activateServerMode`.

---

## Método `_ensureDeviceName`

```dart
Future<void> _ensureDeviceName() async {
  _deviceName = await _deviceNameService.getName();
  final isFirst = await _deviceNameService.isFirstLaunch();
  if (isFirst) {
    await _deviceNameService.generateAndSaveName();
    _deviceName = await _deviceNameService.getName();
  }
}
```

Asegura que el nombre esté configurado. En el primer arranque, genera uno aleatorio automáticamente **sin mostrar ningún modal**.

---

## Método `_buildServerLabel`

```dart
Widget _buildServerLabel() {
  return InkWell(
    onTap: _showConnectDialog,
    child: Icon(
      _hasServer
          ? Icons.wifi_rounded
          : _relay.isRunning
              ? Icons.wifi_tethering_rounded
              : Icons.link_rounded,
      color: (_hasServer || _relay.isRunning) ? AppColors.accentPrimary : AppColors.textMuted,
    ),
  );
}
```

Siempre muestra solo un icono wifi (sin texto). La información completa del servidor (IP, puerto, PIN) está en el ConnectSheet.

---

## Widget `_ConnectSheet`

Bottom sheet tappable desde el icono wifi del header. Muestra una **card unificada** con la info del servidor activo (local o externo) y, debajo, la sección para escanear y cambiar de servidor.

```dart
Widget _buildServerInfoCard({
  required String address,
  required String badgeText,
  required IconData icon,
  String? webAddress,
  String? pin,
  String? description,
})
```

El mismo widget se usa para:
- **Servidor local** (mobile en server mode): icono wifi_tethering, badge "Activo", PIN visible.
- **Servidor externo conectado**: icono wifi, badge "Conectado", sin PIN.

Al presionar "Desconectarse", hace `pushReplacement` a `SplashScreen`.

### Estructura de filas en la card

Las filas de **Servidor**, **Web** y **PIN** usan todas la misma estructura de layout para alineación consistente:

```dart
Row(children: [
  Icon(..., size: 14),
  SizedBox(width: AppSpacing.xs),
  SizedBox(width: 52, child: Text(label)),  // ancho fijo de 52px
  Expanded(child: Text(value)),             // valor ocupa el espacio restante
  // botón copiar (solo en filas URL)
])
```

El `SizedBox` de **52px de ancho fijo** garantiza que los valores de todas las filas (IP del servidor, URL web, PIN) queden alineados verticalmente en la misma columna. Antes de esta corrección, la fila del PIN usaba un layout diferente que desalineaba el valor respecto a las filas de URL.

---

## Clases auxiliares internas

### `_ReceiveBuffer`
Acumula los chunks de un archivo que se está recibiendo vía P2P hasta que llega `send-complete`.

### `_PendingSend`
Guarda el archivo que se quiere enviar mientras se espera la aceptación del receptor.
