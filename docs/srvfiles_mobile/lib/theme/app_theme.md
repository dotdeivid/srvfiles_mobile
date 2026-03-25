# theme/app_theme.dart

**Archivo:** `lib/theme/app_theme.dart`
**Rol:** Define el tema Material 3 oscuro de la app. Configura colores, tipografía, y el estilo de cada componente Material.

---

## Getter estático `AppTheme.dark`

```dart
class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.accentPrimary,
      surface: AppColors.bgPrimary,
      // ...
    ),
    textTheme: _buildTextTheme(),
    // componentes...
  );
}
```

`ThemeData` es el objeto central de theming en Flutter. Se pasa a `MaterialApp(theme: ...)` y todos los widgets Material (`AppBar`, `ElevatedButton`, `TextField`, etc.) lo consultan automáticamente.

`useMaterial3: true` activa la nueva versión del sistema de diseño Material de Google. Material 3 tiene nuevas formas, colores, y componentes.

---

## Función `_buildTextTheme`

```dart
static TextTheme _buildTextTheme() {
  return const TextTheme(
    titleLarge: TextStyle(
      fontFamily: 'Outfit',
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      color: AppColors.textSecondary,
    ),
    // ...
  );
}
```

Define la escala tipográfica: `displayLarge`, `titleMedium`, `bodySmall`, etc. Los nombres son los mismos de Material 3. Los widgets acceden a ellos con `Theme.of(context).textTheme.titleLarge`.

Las fuentes `Outfit` (títulos) e `Inter` (cuerpo) son las mismas que usa el frontend web.

---

## Componentes customizados

### `appBarTheme`

```dart
appBarTheme: const AppBarTheme(
  backgroundColor: AppColors.bgSecondary,
  elevation: 0,
  scrolledUnderElevation: 0,
),
```

`elevation: 0` elimina la sombra de la `AppBar`. `scrolledUnderElevation: 0` evita que Material 3 agregue una sombra automáticamente al hacer scroll.

### `elevatedButtonTheme`

```dart
elevatedButtonTheme: ElevatedButtonThemeData(
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.accentPrimary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
  ),
),
```

Define el estilo por defecto de todos los `ElevatedButton` de la app. Sin esto, cada botón necesitaría especificar su propio estilo.

### `inputDecorationTheme`

```dart
inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: AppColors.bgCard,
  border: OutlineInputBorder(
    borderRadius: AppRadius.borderMd,
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
),
```

Estilo global de todos los `TextField`. `filled: true` activa el fondo de color.

### `dialogTheme`

```dart
dialogTheme: DialogTheme(
  backgroundColor: AppColors.bgSecondary,
  shape: RoundedRectangleBorder(
    borderRadius: AppRadius.borderLg,
    side: const BorderSide(color: AppColors.borderMedium),
  ),
),
```

Estilo de todos los `AlertDialog` y `showDialog`. Define el fondo oscuro y el borde sutil.
