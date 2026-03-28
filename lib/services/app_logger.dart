import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Logger centralizado de SrvFiles.
/// Solo escribe al archivo en WARN+. En debug también muestra en consola.
class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  Logger? _logger;

  Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/SrvFiles/logs')
      ..createSync(recursive: true);
    final file = File('${dir.path}/errors.txt');

    _logger = Logger(
      filter: ProductionFilter(),
      printer: SimplePrinter(printTime: true, colors: false),
      output: MultiOutput([
        if (kDebugMode) ConsoleOutput(),
        _FileOutput(file),
      ]),
    );
  }

  void error(String msg, {Object? error, StackTrace? stack}) =>
      _logger?.e(msg, error: error, stackTrace: stack);
  void warn(String msg) => _logger?.w(msg);
  void info(String msg) => _logger?.i(msg);
  void debug(String msg) => _logger?.d(msg);
}

/// Output que escribe una línea por entrada, solo WARN+.
class _FileOutput extends LogOutput {
  final File file;
  _FileOutput(this.file);

  @override
  void output(OutputEvent event) {
    if (event.level.index < Level.warning.index) return;
    file.writeAsStringSync(
      '${event.lines.join(' ')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
