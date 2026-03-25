# screens/home_screen.dart

**Archivo:** `lib/screens/home_screen.dart`
**Rol:** Pantalla principal de la app. Gestiona archivos del servidor, transferencias P2P, archivos recibidos, polling, y el relay embebido.

---

## Estado

```dart
// Servidor
String? serverUrl;      // null = modo sin servidor
FilesService? _filesService;
AppConfig? _config;
DiskStats? _stats;
List<FileInfo> _files = [];
bool _loading = true;
String? _error;
bool _connectionLost = false;
Timer? _pollTimer;

// P2P
TransferService _transferService = TransferService();
EmbeddedRelay _relay = EmbeddedRelay();
List<TransferClient> _onlineClients = [];
String? _myClientId;
ActiveTransfer? _activeTransfer;
Map<String, _ReceiveBuffer> _receiveBuffers = {};
_PendingSend? _pendingSend;

// Archivos recibidos
ReceivedFilesService _receivedFilesService = ReceivedFilesService();
List<FileInfo> _receivedFiles = [];

// UI
bool _isGridView = false;
String _searchQuery = '';
TextEditingController _searchController = TextEditingController();
List<File> _stagedFiles = [];
bool _uploading = false;
double _uploadProgress = 0;
```

`HomeScreen` tiene mucho estado porque es la pantalla principal que coordina todas las funcionalidades. En una app más grande, este estado se dividiría con un state management como Riverpod o BLoC.

---

## `initState` y `dispose`

```dart
@override
void initState() {
  super.initState();
  _startRelay();
  _loadReceivedFiles();
  _initialLoad();
}

@override
void dispose() {
  _pollTimer?.cancel();
  _transferService.dispose();
  _relay.stop();
  _searchController.dispose();
  super.dispose();
}
```

`initState` se llama una vez cuando el widget se inserta en el árbol. `dispose` se llama cuando el widget se destruye y es el lugar correcto para cancelar timers, cerrar conexiones, y liberar recursos.

---

## Método `_startRelay`

```dart
Future<void> _startRelay() async {
  await _relay.start();
  if (mounted) setState(() {});
}
```

Arranca el relay embebido para que otros dispositivos puedan conectarse. `setState(() {})` sin cambios específicos fuerza un rebuild para que la AppBar muestre la IP del relay.

---

## Método `_initialLoad`

```dart
Future<void> _initialLoad() async {
  if (!_hasServer) {
    setState(() => _loading = false);
    return;
  }
  // Cargar archivos, stats, config en paralelo
  await _refreshData();
  _startPolling();
}
```

Si no hay servidor, solo muestra la pantalla vacía. Si hay servidor, carga todos los datos y arranca el polling.

---

## Método `_refreshData`

```dart
Future<void> _refreshData() async {
  try {
    final results = await Future.wait([
      _filesService!.getFiles(),
      _filesService!.getStats(),
      _filesService!.getConfig(),
    ]);
    if (mounted) {
      setState(() {
        _files = results[0] as List<FileInfo>;
        _stats = results[1] as DiskStats;
        _config = results[2] as AppConfig;
        _connectionLost = false;
        _loading = false;
      });
    }
  } catch (e) {
    // ...
  }
}
```

`Future.wait` ejecuta las tres peticiones HTTP en paralelo. Si falla cualquiera, el `catch` detecta pérdida de conexión.

---

## Método `_startPolling`

```dart
void _startPolling() {
  _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    if (!_connectionLost) _refreshData();
  });
}
```

Refresca los datos cada 5 segundos. `Timer.periodic` en Flutter equivale a `setInterval` en JavaScript. Se cancela en `dispose()`.

---

## Método `_initTransfer`

```dart
void _initTransfer() {
  final wsUrl = '...';
  final deviceName = '...';
  _transferService
    ..onClientsUpdate = (clients) => setState(() => _onlineClients = clients)
    ..onSendRequest = (req) => _showIncomingTransferDialog(req)
    ..onSendAccept = (id) => _handleSendAccept(id)
    ..onSendReject = (id) => setState(() => _activeTransfer = null)
    ..onSendCancel = (id) {
      _receiveBuffers.remove(id);
      setState(() => _activeTransfer = null);
    }
    ..onSendComplete = (id) => _handleReceiveComplete(id)
    ..onBinaryChunk = (id, data) => _handleBinaryChunk(id, data);
  _transferService.connect(wsUrl, 'SrvFiles Mobile', deviceName);
}
```

El operador `..` (cascade) ejecuta múltiples operaciones sobre el mismo objeto. Asigna todos los callbacks antes de llamar `connect`.

---

## Método `_onSendFile`

```dart
Future<void> _onSendFile(String clientId, String peerName) async {
  if (_activeTransfer != null) return;

  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  if (result == null) return;

  // Crear estado de transferencia en espera
  setState(() {
    _activeTransfer = ActiveTransfer(
      transferId: transferId,
      waiting: true,
      direction: TransferDirection.sending,
      // ...
    );
  });

  _transferService.sendRequest(to: clientId, ...);
}
```

Abre el selector de archivos del sistema, crea el estado de la transferencia, y envía la solicitud al receptor. La guarda `_activeTransfer != null` evita iniciar dos transferencias simultáneas.

---

## Método `_handleSendAccept`

```dart
Future<void> _handleSendAccept(String transferId) async {
  // Marcar como activo (ya no waiting)
  setState(() => _activeTransfer = _activeTransfer?.copyWith(waiting: false));

  // Leer archivo completo en memoria
  final fileBytes = await pending.file.readAsBytes();

  // Enviar en chunks con reporte de progreso
  await _transferService.sendFile(
    transferId: pending.transferId,
    fileBytes: fileBytes,
    onProgress: (progress) {
      setState(() => _activeTransfer = _activeTransfer?.copyWith(
        progress: (progress * 100).round(),
      ));
    },
  );
}
```

Cuando el receptor acepta, se lee el archivo completo en memoria (`readAsBytes`) y se envía. Cada vez que `sendFile` reporta progreso, se llama `setState` para actualizar la barra.

---

## Método `_handleReceiveComplete`

```dart
Future<void> _handleReceiveComplete(String transferId) async {
  final buffer = _receiveBuffers.remove(transferId);

  // Ensamblar todos los chunks en un Uint8List
  final totalLength = buffer.chunks.fold<int>(0, (sum, c) => sum + c.length);
  final assembled = Uint8List(totalLength);
  int offset = 0;
  for (final chunk in buffer.chunks) {
    assembled.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }

  // Guardar en disco
  final filePath = await _receivedFilesService.saveFile(
    buffer.fileName, assembled,
  );
  // Mostrar notificación y SnackBar con "Abrir"
}
```

Ensambla los chunks recibidos en un buffer contiguo. `Uint8List(totalLength)` aloca el buffer; `setRange` copia cada chunk en su posición correcta. Luego guarda el archivo y notifica al usuario.

---

## Getter `_filteredFiles`

```dart
List<FileInfo> get _filteredFiles {
  if (_searchQuery.isEmpty) return _files;
  final query = _searchQuery.toLowerCase();
  return _files.where((f) => f.name.toLowerCase().contains(query)).toList();
}
```

Filtra los archivos del servidor según el texto de búsqueda. Al ser un getter (no `setState`), se recalcula en cada `build`. Para listas grandes sería mejor cachearlo con `useMemo` (React) o calcular en `setState`, pero para el uso típico (decenas de archivos) es suficiente.

---

## Métodos de UI

### `_buildLoading`
Muestra el `SkeletonLoader` mientras se carga la primera vez.

### `_buildConnectionBanner`
Banner rojo en la parte superior cuando se pierde la conexión, con botón "Reintentar".

### `_buildServerLabel`
Elemento de la AppBar que muestra la IP del servidor (si conectado) o la IP del relay embebido (si no conectado). Es tappable para abrir el `_ConnectSheet`.

### `_buildGrid` / `_buildList`
Renderizan los archivos del servidor como grid o lista usando `SliverGrid` / `SliverList`. La cantidad de columnas del grid se adapta al ancho de pantalla.

### `_buildReceivedFilesSection`
Sección al final de la pantalla que muestra los archivos recibidos por P2P, siempre visible independientemente de si hay servidor conectado.

---

## Clases auxiliares internas

### `_ReceiveBuffer`
```dart
class _ReceiveBuffer {
  final List<Uint8List> chunks;
  int received;
  final int total;
  final String fileName;
  final String mimeType;
}
```
Acumula los chunks de un archivo que se está recibiendo hasta que llega `send-complete`.

### `_PendingSend`
```dart
class _PendingSend {
  final String transferId;
  final File file;
  final String peerId;
}
```
Guarda el archivo que se quiere enviar mientras se espera que el receptor acepte.

---

## Widget `_ConnectSheet`

Bottom sheet para conectar a un servidor desde `HomeScreen`. Escanea la red, muestra los servidores encontrados, permite conexión manual, y al conectar hace `pushReplacement` con la nueva URL.

Es un `StatefulWidget` separado que encapsula su propio estado de escaneo (`_scanning`, `_servers`). Al ser un widget privado (prefijo `_`), solo es accesible dentro del mismo archivo.
