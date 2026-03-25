# services/transfer_service.dart

**Archivo:** `lib/services/transfer_service.dart`
**Rol:** Cliente WebSocket para el protocolo de transferencia P2P. Gestiona la conexión al relay, envía mensajes de señalización, y retransmite chunks binarios.

---

## Clase `TransferService`

```dart
class TransferService {
  WebSocketChannel? _channel;
  String? clientId;

  // Callbacks
  Function(List<TransferClient>)? onClientsUpdate;
  Function(IncomingTransferRequest)? onSendRequest;
  Function(String transferId)? onSendAccept;
  Function(String transferId)? onSendReject;
  Function(String transferId)? onSendCancel;
  Function(String transferId)? onSendComplete;
  Function(String transferId, Uint8List data)? onBinaryChunk;
}
```

El servicio expone callbacks que `HomeScreen` asigna para recibir eventos. Es el mismo patrón que `TransferConnection` del frontend web.

---

## Método `connect`

```dart
Future<void> connect(String wsUrl, String appName, String deviceName) async {
  _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
  _channel!.stream.listen(
    _onMessage,
    onDone: () { /* desconexión */ },
    onError: (err) { /* error */ },
  );
  // Enviar hello
  _send({ 'type': 'hello', 'appName': deviceName, 'deviceType': 'mobile' });
}
```

Conecta al servidor WebSocket y registra los listeners. `_channel!.stream` es un `Stream<dynamic>` que emite un evento por cada mensaje recibido.

### `WebSocketChannel` vs `WebSocket`

`WebSocketChannel` es del paquete `web_socket_channel` y funciona en Flutter (tanto web como nativo). La clase `WebSocket` de `dart:io` solo funciona en código nativo. Para apps Flutter multiplataforma, `WebSocketChannel` es la opción correcta.

---

## Método `_onMessage`

```dart
void _onMessage(dynamic message) {
  if (message is List<int>) {
    _handleBinary(Uint8List.fromList(message));
  } else if (message is String) {
    _handleJson(jsonDecode(message));
  }
}
```

Distingue entre mensajes binarios (chunks de archivo) y JSON (mensajes de señalización). Los WebSockets pueden enviar ambos tipos en la misma conexión.

---

## Método `_handleBinary`

```dart
void _handleBinary(Uint8List data) {
  // Los primeros 36 bytes son el transferId en ASCII
  final transferId = String.fromCharCodes(data.sublist(0, 36)).trim();
  onBinaryChunk?.call(transferId, data.sublist(36));
}
```

Lee el `transferId` del encabezado del chunk (36 bytes en ASCII) y notifica al `HomeScreen` con los bytes del contenido. El frame binario tiene el formato: `[36 bytes transferId][bytes del archivo]`.

---

## Método `_handleJson`

Despacha el mensaje según su tipo. Ejemplo:

```dart
case 'welcome':
  clientId = msg['clientId'];
  break;
case 'clients':
  final list = (msg['clients'] as List)
      .map((c) => TransferClient.fromJson(c))
      .toList();
  onClientsUpdate?.call(list);
  break;
case 'send-request':
  onSendRequest?.call(IncomingTransferRequest.fromJson(msg));
  break;
// ... etc
```

---

## Método `sendFile`

```dart
Future<void> sendFile({
  required String transferId,
  required Uint8List fileBytes,
  required Function(double) onProgress,
}) async {
  const chunkSize = 64 * 1024; // 64 KB
  int offset = 0;
  final idBytes = Uint8List.fromList(
    transferId.padRight(36).codeUnits,
  );

  while (offset < fileBytes.length) {
    final end = (offset + chunkSize).clamp(0, fileBytes.length);
    final chunkData = fileBytes.sublist(offset, end);
    final frame = Uint8List(idBytes.length + chunkData.length);
    frame.setRange(0, idBytes.length, idBytes);
    frame.setRange(idBytes.length, frame.length, chunkData);

    _channel!.sink.add(frame);
    offset = end;
    onProgress(offset / fileBytes.length);

    // Yield al event loop para no bloquear la UI
    await Future.delayed(Duration.zero);
  }

  sendComplete(transferId);
}
```

Fragmenta el archivo en chunks de 64 KB y los envía uno por uno. Cada chunk tiene el prefijo de 36 bytes del `transferId` para que el relay sepa a quién reenviarlo.

`await Future.delayed(Duration.zero)` cede el control al event loop de Dart después de cada chunk. Sin esto, el loop sincrónico bloquearía la UI durante toda la transferencia.

---

## Método `dispose`

```dart
void dispose() {
  _channel?.sink.close();
  _channel = null;
}
```

Cierra la conexión WebSocket limpiamente. Se llama desde `HomeScreen.dispose()` cuando la pantalla se destruye.
