import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/app_logger.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.init();

    // Errores no capturados → log.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLogger.instance.error('FlutterError: ${details.exceptionAsString()}',
          error: details.exception, stack: details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.error('Uncaught platform error', error: error, stack: stack);
      return true;
    };

    // AES-GCM nativo en Android/iOS: cryptography_flutter se registra solo
    // como plugin, no hace falta llamar a FlutterCryptography.enable().

    // Inicializa sin pedir permisos: el pedido se hace ya con la UI visible.
    await NotificationService().init();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.bgPrimary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    runApp(const SrvFilesApp());
  }, (error, stack) {
    AppLogger.instance.error('Uncaught zone error', error: error, stack: stack);
  });
}

class SrvFilesApp extends StatelessWidget {
  const SrvFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SrvFiles',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
