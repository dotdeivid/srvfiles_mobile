# models/transfer_client.dart

**Archivo:** `lib/models/transfer_client.dart`
**Rol:** Modelo que representa un dispositivo conectado al relay WebSocket. Llega en el mensaje `clients` del servidor.

---

## Clase `TransferClient`

```dart
class TransferClient {
  final String clientId;
  final String appName;
  final bool receiving;
  final String ip;
  final String deviceType; // 'mobile' | 'desktop'
  final bool isServer;
  // ...
}
```

---

## Constructor `fromJson`

```dart
factory TransferClient.fromJson(Map<String, dynamic> json) {
  return TransferClient(
    clientId: json['clientId'] as String,
    appName: json['appName'] as String,
    receiving: json['receiving'] as bool,
    ip: json['ip'] as String,
    deviceType: json['deviceType'] as String,
    isServer: json['isServer'] as bool,
  );
}
```

El servidor envía esta estructura cuando alguien se conecta o desconecta:

```json
{
  "type": "clients",
  "clients": [
    { "clientId": "...", "appName": "Mi PC", "receiving": true, "ip": "192.168.1.5", "deviceType": "desktop", "isServer": true }
  ]
}
```

---

## Getter `isMobile`

```dart
bool get isMobile => deviceType == 'mobile';
```

Getter calculado para evitar comparar strings directamente en los widgets. En el widget `OnlineClients`, se usa para elegir el ícono del dispositivo:

```dart
client.isMobile ? Icons.phone_android : Icons.computer_rounded
```

---

## Campo `isServer`

Indica si este cliente es una instancia Tauri (la versión escritorio de SrvFiles que actúa como servidor). El widget `OnlineClients` usa `isServer` para mostrar el badge `srv` y el botón "Ver" que navega a los archivos de ese servidor.
