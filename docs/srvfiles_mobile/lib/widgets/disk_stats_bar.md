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

`DiskStats?` es nullable. Si `stats == null` (todavía cargando), retorna `SizedBox.shrink()`.

---

## Label

```dart
final label = Text(
  '${formatBytes(s.free)} / ${formatBytes(s.total)}',
  ...
);
```

Muestra el espacio **libre** sobre el total (ej: `"37.6 GB / 50 GB"`). La barra de progreso refleja el espacio usado, pero el texto muestra cuánto queda disponible.

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

La barra visualiza el **espacio usado**: Normal → gradiente accent. Warning (>80% usado) → naranja. Critical (>95% usado) → rojo. Los umbrales vienen del modelo `DiskStats` (`isWarning`, `isCritical`).

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

En modo `fullWidth`, la barra ocupa todo el espacio horizontal disponible (usada en `AppBar.bottom`).

```dart
// HomeScreen:
appBar: AppBar(
  bottom: _isServer && _stats != null
      ? PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: DiskStatsBar(stats: _stats, fullWidth: true),
        )
      : null,
),
```

Usa `_isServer` (no `_hasServer`) para que la barra aparezca tanto cuando hay servidor externo como cuando el propio celular es el servidor. `PreferredSize` es necesario porque `AppBar.bottom` requiere un widget que declare su altura preferida.
