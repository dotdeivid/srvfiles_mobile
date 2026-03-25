# services/notification_service.dart

**Archivo:** `lib/services/notification_service.dart`
**Rol:** Singleton que encapsula el plugin de notificaciones locales. Muestra notificaciones del sistema cuando se completa una descarga o transferencia.

---

## Patrón Singleton

```dart
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
}
```

El patrón singleton garantiza que exista una sola instancia de `NotificationService` en toda la app. El constructor privado `_internal()` impide crear instancias con `NotificationService()` normal; el factory constructor devuelve siempre `_instance`.

¿Por qué singleton? El plugin de notificaciones (`FlutterLocalNotificationsPlugin`) debe inicializarse una sola vez. Con singleton, `init()` solo se ejecuta una vez aunque múltiples partes del código llamen `NotificationService()`.

---

## Método `init`

```dart
Future<void> init() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const settings = InitializationSettings(android: androidInit, iOS: iosInit);
  await _plugin.initialize(settings);
}
```

Inicializa el plugin con la configuración específica de cada plataforma:
- **Android**: `@mipmap/ic_launcher` es el ícono de la app que aparece en la notificación.
- **iOS** (`DarwinInitializationSettings`): usa el nombre Darwin (el kernel de macOS/iOS) porque el plugin es multiplataforma Apple.

---

## Método `showDownloadComplete`

```dart
Future<void> showDownloadComplete(String filename) async {
  await _show(
    id: 1,
    title: 'Descarga completa',
    body: '"$filename" guardado correctamente',
  );
}
```

---

## Método `showTransferComplete`

```dart
Future<void> showTransferComplete(String filename, String peerName) async {
  await _show(
    id: 2,
    title: 'Archivo recibido',
    body: '"$filename" de $peerName',
  );
}
```

---

## Método `_show`

```dart
Future<void> _show({
  required int id,
  required String title,
  required String body,
}) async {
  const androidDetails = AndroidNotificationDetails(
    'srvfiles_channel',
    'SrvFiles',
    importance: Importance.high,
    priority: Priority.high,
  );
  const details = NotificationDetails(android: androidDetails);
  await _plugin.show(id, title, body, details);
}
```

El método interno que realmente muestra la notificación. El `id` es un número entero que identifica la notificación — si se muestra otra con el mismo `id`, reemplaza la anterior (útil para no acumular notificaciones del mismo tipo).

El `channel` de Android (`'srvfiles_channel'`) es un grupo lógico de notificaciones que el usuario puede silenciar individualmente desde la configuración del sistema.
