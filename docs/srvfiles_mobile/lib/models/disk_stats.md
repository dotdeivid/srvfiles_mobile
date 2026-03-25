# models/disk_stats.dart

**Archivo:** `lib/models/disk_stats.dart`
**Rol:** Modelo de estadísticas de disco con getters calculados para la barra de uso. Replica la lógica del componente `DiskStats.tsx` del frontend web.

---

## Clase `DiskStats`

```dart
class DiskStats {
  final int total;  // bytes
  final int free;   // bytes
  final int used;   // bytes
  // ...
}
```

---

## Constructor `fromJson`

```dart
factory DiskStats.fromJson(Map<String, dynamic> json) {
  return DiskStats(
    total: json['total'] as int,
    free: json['free'] as int,
    used: json['used'] as int,
  );
}
```

Deserializa la respuesta del endpoint `/api/files/stats`.

---

## Getter `usedPercent`

```dart
double get usedPercent => total > 0 ? (used / total * 100) : 0;
```

Calcula el porcentaje de disco usado. La guarda `total > 0` evita una división por cero si el servidor reporta un total de 0 (disco no accesible).

---

## Getter `isWarning`

```dart
bool get isWarning => usedPercent >= 80;
```

Retorna `true` cuando se usó el 80% o más del disco. En la UI, esto cambia el color de la barra a amarillo/naranja (`AppColors.warning`).

---

## Getter `isCritical`

```dart
bool get isCritical => usedPercent >= 95;
```

Retorna `true` cuando se usó el 95% o más. En la UI, la barra se pone roja (`AppColors.danger`).

---

## Uso en la app

`DiskStats` se pasa al widget `DiskStatsBar` que muestra la barra en la `AppBar` de `HomeScreen`. La lógica de colores (`isWarning`, `isCritical`) vive en el modelo para que tanto la barra como cualquier otro widget que pudiera mostrar estadísticas compartan exactamente el mismo criterio.
