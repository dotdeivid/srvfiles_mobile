# models/active_transfer.dart

**Archivo:** `lib/models/active_transfer.dart`
**Rol:** Modelo que representa el estado de una transferencia P2P activa (enviando o recibiendo). Incluye dirección, progreso, y si está esperando aceptación.

---

## Enum `TransferDirection`

```dart
enum TransferDirection { sending, receiving }
```

En Dart, los `enum` son tipos con un conjunto fijo de valores. `TransferDirection` tiene exactamente dos estados posibles: `sending` (soy el remitente) o `receiving` (soy el receptor). Usar un enum en lugar de un string `'sending'` / `'receiving'` hace que el compilador detecte valores inválidos.

---

## Clase `ActiveTransfer`

```dart
class ActiveTransfer {
  final String transferId;
  final String fileName;
  final int fileSize;
  final int progress;         // 0-100
  final TransferDirection direction;
  final String peerName;
  final String peerId;
  final bool waiting;         // esperando que el receptor acepte
  // ...
}
```

Todos los campos son `final` porque `ActiveTransfer` es inmutable. En Flutter, el estado inmutable es un patrón recomendado: en lugar de modificar el objeto, se crea uno nuevo con `copyWith`.

---

## Método `copyWith`

```dart
ActiveTransfer copyWith({
  String? transferId,
  String? fileName,
  int? fileSize,
  int? progress,
  TransferDirection? direction,
  String? peerName,
  String? peerId,
  bool? waiting,
}) {
  return ActiveTransfer(
    transferId: transferId ?? this.transferId,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    progress: progress ?? this.progress,
    direction: direction ?? this.direction,
    peerName: peerName ?? this.peerName,
    peerId: peerId ?? this.peerId,
    waiting: waiting ?? this.waiting,
  );
}
```

### ¿Por qué `copyWith`?

En `HomeScreen`, cuando llega un chunk de archivo se actualiza el progreso:

```dart
_activeTransfer = _activeTransfer?.copyWith(progress: progress);
```

Con `copyWith`, solo se especifican los campos que cambian; el resto se conserva del objeto anterior. El operador `??` (null-coalescing) significa "si el parámetro es null, usá el valor actual".

Este patrón es idéntico a cómo funciona el spread de objetos en React: `{ ..._activeTransfer, progress }`.

---

## Campo `waiting`

```dart
final bool waiting;
```

Cuando el remitente envía `send-request`, la transferencia existe pero todavía no se aprobó. `waiting: true` hace que la UI muestre "Esperando respuesta..." en lugar de una barra de progreso.

Cuando el receptor acepta y llega `send-accept`, el `HomeScreen` llama:
```dart
_activeTransfer = _activeTransfer?.copyWith(waiting: false);
```
