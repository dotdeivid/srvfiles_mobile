# widgets/disk_stats_bar.dart

**Archivo:** `lib/widgets/disk_stats_bar.dart`
**Rol:** Barra visual de uso de disco. Tiene dos modos: compacto vertical (para usar en la AppBar) y horizontal de ancho completo. Replica `DiskStats.tsx` del frontend web.

---

## Props

```dart
class DiskStatsBar extends StatelessWidget {
  const DiskStatsBar({super.key, required this.stats, this.fullWidth = false});

  final DiskStats? stats;      // null = no mostrar nada
  final bool fullWidth;        // true = barra horizontal en AppBar.bottom
}
```

`DiskStats?` es nullable. Si `stats == null` (todavía cargando), retorna `SizedBox.shrink()` — un widget de tamaño cero que no ocupa espacio.

---

## Lógica de color

```dart
if (s.isCritical) {
  fillColor = AppColors.danger;
} else if (s.isWarning) {
  fillColor = AppColors.warning;
} else {
  fillColor = Colors.transparent;
  fillGradient = AppColors.accentGradient;
}
```

Normal → gradiente accent (azul/teal). Warning (>80%) → naranja. Critical (>95%) → rojo. Los criterios vienen del modelo `DiskStats`.

---

## Widget `AnimatedFractionallySizedBox`

```dart
AnimatedFractionallySizedBox(
  duration: const Duration(milliseconds: 400),
  curve: Curves.ease,
  widthFactor: percent.clamp(0.0, 1.0),
  child: Container(decoration: ...),
),
```

Anima el ancho de la barra cuando cambia el porcentaje. `widthFactor: 0.65` hace que el widget ocupe el 65% del ancho disponible. `.clamp(0.0, 1.0)` garantiza que nunca se salga del rango [0, 1].

`FractionallySizedBox` es una forma elegante de expresar anchos relativos sin hacer cálculos manuales con `MediaQuery`.

---

## Modo `fullWidth`

```dart
if (fullWidth) {
  return Padding(
    padding: ...,
    child: Row(children: [label, SizedBox(...), Expanded(child: bar)]),
  );
}
```

En modo `fullWidth`, la barra ocupa todo el espacio horizontal disponible (usada en `AppBar.bottom`). `Expanded` le da al widget de la barra todo el espacio que el `Row` no usa para el label.

```dart
// HomeScreen:
appBar: AppBar(
  bottom: _hasServer && _stats != null
      ? PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: DiskStatsBar(stats: _stats, fullWidth: true),
        )
      : null,
),
```

`PreferredSize` es necesario porque `AppBar.bottom` requiere un widget que declare su altura preferida.
