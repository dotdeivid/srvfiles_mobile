import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio de notificaciones locales para descargas y transferencias completadas.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

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
