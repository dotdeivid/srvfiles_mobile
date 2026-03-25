# main.dart

**Archivo:** `lib/main.dart`
**Rol:** Punto de entrada de la app Flutter. Inicializa servicios globales, configura la barra de sistema, y monta el widget raíz.

---

## Función `main`

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SrvFilesApp());
}
```

### `WidgetsFlutterBinding.ensureInitialized()`

Flutter separa el motor de renderizado del framework de widgets. Antes de poder llamar código de plataforma (plugins, FFI, etc.), el motor debe estar inicializado. Si `main` es `async` y llama a plugins antes de `runApp`, esta línea es obligatoria.

Sin ella, llamar `NotificationService().init()` lanzaría un error porque el canal de comunicación con la plataforma nativa todavía no existe.

### `await NotificationService().init()`

Inicializa el plugin de notificaciones de forma asíncrona antes de que la app arranque. Esto es necesario porque en iOS hay que registrar el canal de notificaciones antes del primer frame, no después.

### `SystemChrome.setSystemUIOverlayStyle`

Controla el aspecto de la barra de estado del sistema operativo (la franja superior con la hora e iconos de señal):
- **`statusBarColor: Colors.transparent`**: la barra de estado es transparente, el contenido de la app se ve detrás.
- **`statusBarIconBrightness: Brightness.light`**: los íconos de la barra de estado son blancos (para fondos oscuros).

Esto es parte de la integración con el tema dark de la app.

---

## Widget `SrvFilesApp`

```dart
class SrvFilesApp extends StatelessWidget {
  const SrvFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SrvFiles',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
```

`SrvFilesApp` es el widget raíz. Es un `StatelessWidget` porque no tiene estado propio — solo configura el `MaterialApp`.

### `MaterialApp`

El widget de nivel más alto de una app Material Design. Configura:
- **`title`**: nombre de la app que aparece en el task switcher del sistema operativo.
- **`debugShowCheckedModeBanner: false`**: elimina el banner rojo "DEBUG" que aparece en la esquina en modo desarrollo.
- **`theme: AppTheme.dark`**: el tema visual completo definido en `lib/theme/app_theme.dart`.
- **`home: SplashScreen()`**: la primera pantalla que ve el usuario.

### ¿Por qué `SplashScreen` y no `HomeScreen`?

La `SplashScreen` se encarga de detectar automáticamente si hay un servidor SrvFiles en la red local y, si lo hay, conectarse antes de mostrar la pantalla principal. Si se fuera directo a `HomeScreen`, el usuario vería la app vacía y tendría que conectar manualmente.
