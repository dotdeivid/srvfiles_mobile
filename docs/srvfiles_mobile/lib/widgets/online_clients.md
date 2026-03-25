# widgets/online_clients.dart

**Archivo:** `lib/widgets/online_clients.dart`
**Rol:** Lista de dispositivos conectados al relay WebSocket. Muestra nombre, tipo, IP, botones de acción, y barra de progreso de transferencia activa.

---

## Componentes

```
OnlineClients (StatelessWidget)
└── _ClientRow (StatelessWidget)
```

---

## Widget `OnlineClients`

```dart
class OnlineClients extends StatelessWidget {
  final List<TransferClient> clients;
  final String? myClientId;
  final ActiveTransfer? activeTransfer;
  final void Function(String clientId, String peerName) onSendFile;
  final VoidCallback onCancelTransfer;
  final void Function(String serverUrl)? onViewServer;
}
```

Filtra la lista para excluir al propio dispositivo:

```dart
final others = clients.where((c) => c.clientId != myClientId).toList();
if (others.isEmpty) return const SizedBox.shrink();
```

Si no hay otros dispositivos, retorna un widget vacío. `SizedBox.shrink()` es la forma idiomática de "no renderizar nada" en Flutter (equivalente a `return null` en React).

### `AnimatedSize`

```dart
AnimatedSize(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeOutCubic,
  child: Container(...),
)
```

Anima el cambio de altura cuando se agregan o eliminan dispositivos de la lista. Sin esto, la lista "saltaría" al cambiar de tamaño.

---

## Widget `_ClientRow`

Renderiza un dispositivo. Los estados posibles:

- `isThisRow`: hay una transferencia activa con este dispositivo.
- `isOtherRow`: hay una transferencia activa pero con otro dispositivo.

```dart
final isThisRow = activeTransfer?.peerId == client.clientId;
final isOtherRow = activeTransfer != null && !isThisRow;
```

Cuando `isOtherRow == true`, los botones de "Enviar" están deshabilitados (solo puede haber una transferencia a la vez).

### Ícono del dispositivo

```dart
Icon(
  client.isMobile
      ? Icons.phone_android
      : client.isServer
          ? Icons.computer_rounded
          : Icons.language,
)
```

- Móvil: teléfono.
- Servidor Tauri (isServer): computadora.
- Desktop web (no isServer): globo de Internet.

### Badge `srv`

```dart
if (client.isServer) ...[
  Container(
    child: Text('srv', style: TextStyle(color: AppColors.accentPrimary)),
  ),
],
```

El operador `...` (spread) en una lista de widgets de Flutter es el equivalente de `&&` en JSX: solo agrega los widgets si la condición es verdadera.

### Barra de progreso

La barra de progreso solo aparece en `isThisRow`. Usa `AnimatedFractionallySizedBox` con el gradiente accent, igual que `DiskStatsBar`.

Si `activeTransfer.waiting == true`, muestra "Esperando respuesta..." en lugar de la barra.
