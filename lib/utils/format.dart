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
  if (bytes <= 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  final i = min((log(bytes) / log(k)).floor(), sizes.length - 1);
  final value = bytes / pow(k, i);
  // Mostrar 1 decimal, pero sin ".0" innecesario
  final formatted = value % 1 == 0
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$formatted ${sizes[i]}';
}

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// Formatea un ISO 8601 string a formato legible estilo es-ES.
/// Ejemplo: "2026-03-17T01:30:00.000Z" → "17 mar 2026, 01:30"
///
/// Los nombres de mes van fijos para no depender de
/// `initializeDateFormatting('es')`. Devuelve '' si la fecha no es válida.
String formatDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return '';
  final date = parsed.toLocal();
  final time = DateFormat('HH:mm').format(date);
  return '${date.day} ${_months[date.month - 1]} ${date.year}, $time';
}
