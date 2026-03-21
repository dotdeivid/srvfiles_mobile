import 'dart:math';
import 'package:intl/intl.dart' show DateFormat;

/// Convierte bytes a string legible (base 1024).
/// Misma lógica que formatBytes() del frontend web.
///
/// Ejemplos:
///   formatBytes(0)          → "0 B"
///   formatBytes(1536)       → "1.5 KB"
///   formatBytes(1073741824) → "1 GB"
String formatBytes(int bytes) {
  if (bytes == 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(k)).floor();
  final value = bytes / pow(k, i);
  // Mostrar 1 decimal, pero sin ".0" innecesario
  final formatted = value % 1 == 0
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$formatted ${sizes[i]}';
}

/// Formatea un ISO 8601 string a formato legible estilo es-ES.
/// Ejemplo: "2026-03-17T01:30:00.000Z" → "17 mar 2026, 01:30"
String formatDate(String isoDate) {
  final date = DateTime.parse(isoDate).toLocal();
  return DateFormat("d MMM yyyy, HH:mm", 'es').format(date);
}
