# utils/format.dart

**Archivo:** `lib/utils/format.dart`
**Rol:** Funciones de formato para bytes y fechas. Replica `formatBytes()` y `formatDate()` del frontend web.

---

## Función `formatBytes`

```dart
String formatBytes(int bytes) {
  if (bytes == 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor();
  final value = bytes / pow(1024, i);
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${suffixes[i]}';
}
```

### Algoritmo

Usa logaritmos para determinar la unidad apropiada:

- `log(bytes) / log(1024)` calcula el logaritmo en base 1024 de los bytes.
- `.floor()` lo redondea hacia abajo para obtener el índice de la unidad.

Ejemplos:
- `1024` → `log(1024)/log(1024) = 1` → `1.0 KB`
- `1500000` → `log(1500000)/log(1024) ≈ 2.06` → índice 2 → MB → `1.4 MB`

### `toStringAsFixed`

- Si el valor es ≥ 100 (ej: `512 MB`), no muestra decimales: `"512 MB"`.
- Si es < 100 (ej: `1.4 MB`), muestra 1 decimal: `"1.4 MB"`.

---

## Función `formatDate`

```dart
String formatDate(String isoDate) {
  final date = DateTime.parse(isoDate);
  return DateFormat('dd/MM/yyyy', 'es').format(date);
}
```

Convierte una fecha ISO 8601 (`"2026-03-20T14:30:00.000Z"`) a un formato legible (`"20/03/2026"`).

### `DateFormat` del paquete `intl`

El paquete `intl` provee formateo de fechas respetando el locale. `'es'` especifica español, lo que afecta el nombre de los meses y el orden de los componentes.

`DateTime.parse` analiza strings ISO 8601 directamente. Si el string no es una fecha válida, lanza una `FormatException`.
