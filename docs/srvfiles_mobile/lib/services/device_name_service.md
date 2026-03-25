# services/device_name_service.dart

**Archivo:** `lib/services/device_name_service.dart`
**Rol:** Gestiona el nombre del dispositivo con persistencia en `SharedPreferences`. Genera un nombre aleatorio en el primer lanzamiento.

---

## Persistencia con `SharedPreferences`

`SharedPreferences` es un almacenamiento clave-valor persistente que sobrevive al cierre de la app. Es el equivalente de `localStorage` en el navegador. Internamente usa `NSUserDefaults` en iOS y `SharedPreferences` de Android.

---

## Función `_randomName`

```dart
String _randomName() {
  const adjectives = ['Veloz', 'Azul', 'Solar', ...];
  const nouns = ['Halcón', 'Puma', 'Río', ...];
  final rand = Random();
  return '${adjectives[rand.nextInt(adjectives.length)]} ${nouns[rand.nextInt(nouns.length)]}';
}
```

Genera nombres del estilo "Veloz Halcón" combinando un adjetivo y un sustantivo al azar. El mismo patrón que el frontend web (`randomName()` en `useDeviceName.ts`).

---

## Función `getName`

```dart
Future<String> getName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('device_name') ?? _randomName();
}
```

Lee el nombre guardado. Si no hay ninguno (primera vez), genera uno aleatorio. No lo guarda todavía — eso lo hace `saveName`.

---

## Función `saveName`

```dart
Future<void> saveName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('device_name', name);
}
```

Persiste el nombre elegido por el usuario.

---

## Función `isFirstLaunch`

```dart
Future<bool> isFirstLaunch() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('device_name') == null;
}
```

Retorna `true` si nunca se guardó un nombre. Usado en `SplashScreen` para decidir si mostrar el diálogo `NameDialog` antes de continuar.

---

## Función `generateRandomName`

```dart
String generateRandomName() => _randomName();
```

Wrapper público de `_randomName()` para que otros módulos puedan generar un nombre aleatorio sin guardar nada. Usado cuando se necesita mostrar un nombre de placeholder en la UI.
