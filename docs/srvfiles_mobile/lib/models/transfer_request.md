# models/transfer_request.dart

**Archivo:** `lib/models/transfer_request.dart`
**Rol:** Modelo que representa una solicitud de transferencia entrante. Llega cuando otro dispositivo quiere enviarnos un archivo.

---

## Clase `IncomingTransferRequest`

```dart
class IncomingTransferRequest {
  final String transferId;
  final String from;         // clientId del remitente
  final String fromName;     // nombre legible del remitente
  final String fileName;
  final int fileSize;
  final String mimeType;
  // ...
}
```

---

## Constructor `fromJson`

```dart
factory IncomingTransferRequest.fromJson(Map<String, dynamic> json) {
  return IncomingTransferRequest(
    transferId: json['transferId'] as String,
    from: json['from'] as String,
    fromName: json['fromName'] as String,
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int,
    mimeType: json['mimeType'] as String,
  );
}
```

Se llama cuando llega el mensaje WebSocket de tipo `send-request`:

```json
{
  "type": "send-request",
  "transferId": "...",
  "from": "uuid-del-remitente",
  "fromName": "Mi PC",
  "fileName": "documento.pdf",
  "fileSize": 512000,
  "mimeType": "application/octet-stream"
}
```

---

## Flujo de uso

1. `TransferService._handleJson()` recibe el mensaje `send-request` y crea un `IncomingTransferRequest`.
2. Se invoca el callback `onSendRequest` del `HomeScreen`.
3. `HomeScreen` llama `_showIncomingTransferDialog(request)`.
4. El widget `IncomingTransferDialog` muestra `request.fromName`, `request.fileName`, y `formatBytes(request.fileSize)`.
5. Si el usuario acepta, se llama `_acceptTransfer(request)` que usa `request.transferId` y `request.fileSize` para crear el buffer de recepción.
