import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_logger.dart';

/// Servicio de notificaciones locales para descargas y transferencias completadas.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _foregroundRunning = false;
  bool _permissionRequested = false;

  static const _idForeground = 1;

  /// Contador para ids únicos (los basados en el segundo actual se pisaban).
  int _nextId = 100;

  /// Se llama con el payload cuando el usuario toca una notificación (ruta del
  /// archivo recibido/descargado). Lo registra la pantalla principal.
  void Function(String payload)? onTap;

  /// Inicializa el plugin sin pedir permisos (no bloquea el arranque).
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onTap?.call(payload);
        },
      );
      _initialized = true;
      AppLogger.instance.info('[NotificationService] initialized');
    } catch (e) {
      AppLogger.instance.error('[NotificationService] init failed', error: e);
    }
  }

  /// Pide el permiso de notificaciones (Android 13+ / iOS). Se llama después
  /// de mostrar la primera pantalla, no antes de `runApp`.
  Future<void> requestPermission() async {
    if (!_initialized || _permissionRequested) return;
    _permissionRequested = true;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true);
      }
    } catch (e) {
      AppLogger.instance.warn('[NotificationService] permission request failed: $e');
    }
  }

  /// Muestra una notificación de descarga completada.
  Future<void> showDownloadComplete(String fileName, {String? path}) async {
    await _show(
      title: 'Descarga completada',
      body: '"$fileName" se descargó correctamente',
      payload: path,
    );
  }

  /// Muestra una notificación de transferencia P2P completada.
  Future<void> showTransferComplete(String fileName, String fromName, {String? path}) async {
    await _show(
      title: 'Archivo recibido',
      body: '"$fileName" de $fromName',
      payload: path,
    );
  }

  /// Muestra una notificación de solicitud de transferencia entrante.
  /// Solo si la app no está en primer plano (en primer plano ya hay diálogo).
  Future<void> showIncomingTransfer(String fromName, String fileName) async {
    if (_isAppInForeground) return;
    await _show(
      title: '$fromName quiere enviarte un archivo',
      body: '"$fileName" — Abrí la app para aceptar o rechazar',
    );
  }

  bool get _isAppInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  // ─── Foreground service (Android) ──────────────────────────────────
  // Mantiene el proceso vivo cuando la pantalla se bloquea.
  // En iOS no hay equivalente: la conexión se suspende al ir al background.

  /// Inicia el foreground service en Android. Idempotente.
  Future<void> startForeground() async {
    if (!_initialized || !Platform.isAndroid || _foregroundRunning) return;

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

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.startForegroundService(
            id: _idForeground,
            title: 'SrvFiles',
            body: 'Conexión activa en segundo plano',
            notificationDetails: androidDetails,
            foregroundServiceTypes: {
              AndroidServiceForegroundType.foregroundServiceTypeDataSync,
            },
          );
      _foregroundRunning = true;
    } catch (e) {
      // Android 12+ puede rechazar el inicio desde segundo plano.
      AppLogger.instance.warn('[NotificationService] startForeground failed: $e');
    }
  }

  /// Detiene el foreground service.
  Future<void> stopForeground() async {
    if (!Platform.isAndroid || !_foregroundRunning) return;
    _foregroundRunning = false;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.stopForegroundService();
      await _plugin.cancel(id: _idForeground);
    } catch (e) {
      AppLogger.instance.warn('[NotificationService] stopForeground failed: $e');
    }
  }

  Future<void> _show({
    required String title,
    required String body,
    String? payload,
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

    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      AppLogger.instance.debug('[NotificationService] notification shown: $title');
    } catch (e) {
      AppLogger.instance.error('[NotificationService] show failed', error: e);
    }
  }
}
