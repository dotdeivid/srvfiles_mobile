# widgets/glass_card.dart

**Archivo:** `lib/widgets/glass_card.dart`
**Rol:** Tarjeta con efecto glassmorphism (vidrio esmerilado). Usado en el grid de archivos y otros elementos con fondo translúcido y blur.

---

## Props

```dart
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double blurSigma;        // intensidad del blur, default 20
}
```

Todos los parámetros excepto `child` son opcionales con valores por defecto. Esto permite usar `GlassCard(child: ...)` en el caso más simple, o personalizar completamente cuando sea necesario.

---

## Efecto glassmorphism

```dart
ClipRRect(
  borderRadius: radius,
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    child: Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.bgCard,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.borderSubtle),
      ),
      // ...
    ),
  ),
),
```

### `BackdropFilter`

Aplica un filtro sobre todo lo que está detrás del widget en la pantalla. `ImageFilter.blur` desenfoca el fondo, creando el efecto de vidrio esmerilado.

**Importante**: `BackdropFilter` necesita que su widget padre tenga `ClipRRect` (u otro widget de clipping) para que el blur no se extienda fuera de los bordes del card.

### `blurSigma`

El sigma del desenfoque gaussiano. Un valor de 20 es visible pero no excesivo. Valores muy altos (>50) degradan el rendimiento porque requieren procesar más píxeles.

### `dart:ui`

`ImageFilter` viene de `dart:ui`, la capa de bajo nivel de Flutter que expone APIs del motor de renderizado. No es del framework de widgets (`package:flutter/material.dart`) sino del motor en sí.
