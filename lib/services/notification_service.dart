import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio de notificaciones locales para descargas y transferencias completadas.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _idForeground = 1;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;

    // Android 13+ requiere solicitar el permiso en runtime
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    }
  }

  /// Muestra una notificación de descarga completada.
  Future<void> showDownloadComplete(String fileName) async {
    await _show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Descarga completada',
      body: '"$fileName" se descargó correctamente',
    );
  }

  /// Muestra una notificación de transferencia P2P completada.
  Future<void> showTransferComplete(String fileName, String fromName) async {
    await _show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Archivo recibido',
      body: '"$fileName" de $fromName',
    );
  }

  /// Muestra una notificación de solicitud de transferencia entrante.
  Future<void> showIncomingTransfer(String fromName, String fileName) async {
    await _show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '$fromName quiere enviarte un archivo',
      body: '"$fileName" — Abrí la app para aceptar o rechazar',
    );
  }

  // ─── Foreground service (Android) ──────────────────────────────────
  // Mantiene el proceso vivo cuando la pantalla se bloquea.
  // En iOS no hay equivalente: la conexión se suspende al ir al background.

  /// Inicia la notificación persistente de foreground service en Android.
  Future<void> startForeground() async {
    if (!_initialized || !Platform.isAndroid) return;

    const androidDetails = AndroidNotificationDetails(
      'srvfiles_bg',
      'SrvFiles activo',
      channelDescription: 'Mantiene la conexión activa en segundo plano',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      playSound: false,
      enableVibration: false,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.startForegroundService(
          _idForeground,
          'SrvFiles',
          'Conexión activa en segundo plano',
          notificationDetails: androidDetails,
        );

    // Fallback: mostrar como notificación persistente si startForegroundService
    // no está disponible en la versión del plugin.
    await _plugin.show(_idForeground, 'SrvFiles',
        'Conexión activa en segundo plano', details);
  }

  /// Detiene el foreground service.
  Future<void> stopForeground() async {
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.stopForegroundService();
    await _plugin.cancel(_idForeground);
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'srvfiles_transfers',
      'Transferencias',
      channelDescription: 'Notificaciones de descargas y transferencias',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details);
  }
}
