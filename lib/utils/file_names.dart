import 'dart:io';
import 'package:path/path.dart' as p;

/// Utilidades de nombres de archivo compartidas por los servicios que guardan
/// archivos en disco (recibidos por P2P, descargas y modo servidor).

/// Devuelve un nombre seguro para guardar: solo el último componente de la
/// ruta, sin separadores, caracteres reservados ni secuencias `..`.
///
/// `../../algo.txt` → `algo.txt`; `a/b\\c.txt` → `c.txt`.
String sanitizeFileName(String name) {
  // Quedarse con el último componente, tanto con '/' como con '\'.
  var result = name.split(RegExp(r'[/\\]')).last;
  result = result.replaceAll(RegExp(r'[\x00-\x1f:*?"<>|]'), '_');
  result = result.replaceAll(RegExp(r'\.{2,}'), '_');
  result = result.trim();
  if (result.isEmpty || result == '.') return 'archivo';
  return result;
}

/// true si [name] es un nombre plano (sin rutas ni `..`) que se puede resolver
/// dentro de un directorio. Se usa al leer o borrar, donde no hay que
/// transformar el nombre sino rechazarlo.
bool isPlainFileName(String name) {
  if (name.isEmpty || name == '.' || name == '..') return false;
  if (name.contains('/') || name.contains('\\') || name.contains('\x00')) {
    return false;
  }
  return true;
}

/// Resuelve [name] dentro de [dir] y devuelve el archivo solo si la ruta
/// resultante queda dentro del directorio. Null si el nombre no es válido.
File? resolveInside(Directory dir, String name) {
  if (!isPlainFileName(name)) return null;
  final base = p.normalize(p.absolute(dir.path));
  final target = p.normalize(p.join(base, name));
  if (!p.isWithin(base, target)) return null;
  return File(target);
}

/// Separa nombre y extensión. Los nombres que empiezan por punto
/// (`.gitignore`) se tratan como nombre sin extensión.
({String base, String ext}) splitExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return (base: name, ext: '');
  return (base: name.substring(0, dot), ext: name.substring(dot));
}

/// Devuelve un archivo en [dir] que todavía no existe, agregando ` (n)` antes
/// de la extensión si [name] ya está ocupado.
Future<File> uniqueFileIn(Directory dir, String name) async {
  var target = File(p.join(dir.path, name));
  if (!await target.exists()) return target;
  final parts = splitExtension(name);
  var i = 1;
  while (await target.exists()) {
    target = File(p.join(dir.path, '${parts.base} ($i)${parts.ext}'));
    i++;
  }
  return target;
}
