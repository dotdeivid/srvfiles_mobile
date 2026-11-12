import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Logger centralizado de SrvFiles.
/// Solo escribe al archivo en WARN+. En debug también muestra en consola.
///
/// El archivo rota al superar [_maxLogBytes] (se conserva una copia
/// `errors.1.txt`) y se escribe de forma asíncrona, sin bloquear la UI.
class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  static const _maxLogBytes = 1024 * 1024; // 1 MB

  Logger? _logger;
  File? _file;

  /// Archivo de log actual (para "Compartir logs"), o null si no hay.
  File? get logFile => _file;

  /// Inicializa el logger. Nunca lanza: si no se puede abrir el archivo, se
  /// sigue solo con consola.
  Future<void> init() async {
    File? file;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/SrvFiles/logs');
      await dir.create(recursive: true);
      file = File('${dir.path}/errors.txt');
      await _rotateIfNeeded(file);
      _file = file;
    } catch (e) {
      debugPrint('[AppLogger] no se pudo abrir el archivo de log: $e');
    }

    _logger = Logger(
      filter: kDebugMode ? DevelopmentFilter() : ProductionFilter(),
      printer: SimplePrinter(printTime: true, colors: false),
      output: MultiOutput([
        if (kDebugMode) ConsoleOutput(),
        if (file != null) _FileOutput(file),
      ]),
    );
  }

  static Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) return;
    if (await file.length() < _maxLogBytes) return;
    final old = File(file.path.replaceFirst(RegExp(r'\.txt$'), '.1.txt'));
    if (await old.exists()) await old.delete();
    await file.rename(old.path);
  }

  void error(String msg, {Object? error, StackTrace? stack}) =>
      _logger?.e(msg, error: error, stackTrace: stack);
  void warn(String msg) => _logger?.w(msg);
  void info(String msg) => _logger?.i(msg);
  void debug(String msg) => _logger?.d(msg);
}

/// Output que escribe una línea por entrada, solo WARN+, con un IOSink
/// abierto (sin flush síncrono por línea) y rotación por tamaño.
class _FileOutput extends LogOutput {
  final File file;
  IOSink? _sink;
  int _bytes = 0;

  _FileOutput(this.file) {
    try {
      _bytes = file.existsSync() ? file.lengthSync() : 0;
    } catch (_) {}
  }

  @override
  void output(OutputEvent event) {
    if (event.level.index < Level.warning.index) return;
    final line = '${event.lines.join(' ')}\n';
    try {
      if (_bytes > AppLogger._maxLogBytes) {
        _sink?.close();
        _sink = null;
        final old = File(file.path.replaceFirst(RegExp(r'\.txt$'), '.1.txt'));
        if (old.existsSync()) old.deleteSync();
        if (file.existsSync()) file.renameSync(old.path);
        _bytes = 0;
      }
      _sink ??= file.openWrite(mode: FileMode.append);
      _sink!.write(line);
      _bytes += line.length;
    } catch (_) {
      // El log nunca debe tumbar la app.
    }
  }

  @override
  Future<void> destroy() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
