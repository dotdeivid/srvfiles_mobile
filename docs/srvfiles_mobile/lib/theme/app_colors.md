# theme/app_colors.dart

**Archivo:** `lib/theme/app_colors.dart`
**Rol:** Design tokens de color, espaciado, y bordes. Replica 1:1 las variables CSS del frontend web, garantizando que ambas apps tengan la misma identidad visual.

---

## Clase `AppColors`

```dart
class AppColors {
  static const Color bgPrimary = Color(0xFF0a0a0f);
  static const Color bgSecondary = Color(0xFF12121a);
  static const Color bgCard = Color(0xFF1a1a24);
  // ...
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF6c63ff), Color(0xFF4ecdc4)],
  );
}
```

Todos los campos son `static const`: accesibles sin crear instancia y evaluados en tiempo de compilación. Se usan directamente en widgets: `color: AppColors.accentPrimary`.

### Equivalencias con el frontend web

| CSS variable | AppColors |
|---|---|
| `--bg-primary` | `AppColors.bgPrimary` |
| `--accent-primary` | `AppColors.accentPrimary` |
| `--text-muted` | `AppColors.textMuted` |
| `--danger` | `AppColors.danger` |
| `--warning` | `AppColors.warning` |

El gradiente `accentGradient` replica el `linear-gradient(135deg, #6c63ff, #4ecdc4)` del CSS.

---

## Clase `AppSpacing`

```dart
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}
```

Sistema de espaciado en múltiplos de 4px. El mismo sistema que el frontend web (`--spacing-sm: 8px`, etc.). Todos los `Padding`, `SizedBox`, y márgenes usan estas constantes.

---

## Clase `AppRadius`

```dart
class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;

  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
}
```

Radios de bordes predefinidos. Los `BorderRadius.all(...)` constantes son convenientes para usar directamente en `BoxDecoration`:

```dart
decoration: BoxDecoration(borderRadius: AppRadius.borderMd)
```

En lugar de escribir `BorderRadius.circular(10)` en cada widget.
