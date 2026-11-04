// frontend/lib/services/reminder_notification_service.dart
//
// US8 - Alertas y notificaciones de fechas límite.
//
// Android: las notificaciones push las envía el servidor (FCM) a 1 día, 30 min
// y al vencimiento. Aquí se muestran cuando la app está en primer plano, se
// gestiona el toque (redirección al detalle) y se retiran las ya mostradas
// cuando la actividad se completa.
//
// Web: no hay push configurado, así que se programan alertas locales del
// navegador (Web Notifications API + alerta dentro de la app) con los mismos
// tiempos previos mientras la app esté abierta.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/activity_item.dart';
import 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart' as browser;
import 'reminder_schedule.dart';

typedef OpenItemCallback = void Function(String itemId);
typedef InAppAlertCallback = void Function(ReminderTrigger trigger);
typedef RefreshCallback = Future<void> Function();

class ReminderNotificationService {
  ReminderNotificationService._();
  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  static const String androidChannelId = 'fcm_default_channel';
  static const String androidChannelName = 'Recordatorios y vencimientos';

  /// Los temporizadores web no se programan más allá de este margen; la
  /// sincronización periódica los volverá a programar cuando se acerquen.
  static const Duration maxTimerDelay = Duration(days: 2);
  static const Duration periodicSyncInterval = Duration(minutes: 5);

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final Map<String, List<Timer>> _webTimers = {};
  final Set<String> _firedTriggerKeys = {};
  final Set<String> _shownItemIds = {};

  OpenItemCallback? _onOpenItem;
  InAppAlertCallback? _onInAppAlert;
  Timer? _periodicSyncTimer;
  String? _launchItemId;
  bool _initialized = false;
  bool _pushEnabled = false;

  /// `true` cuando Firebase Messaging está disponible (sólo Android).
  bool get isPushEnabled => _pushEnabled;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize({
    required OpenItemCallback onOpenItem,
    InAppAlertCallback? onInAppAlert,
    bool pushEnabled = false,
  }) async {
    _onOpenItem = onOpenItem;
    _onInAppAlert = onInAppAlert;
    _pushEnabled = pushEnabled;
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      // No se espera la respuesta del usuario para no bloquear el arranque.
      unawaited(requestPermission());
      return;
    }

    if (_isAndroid) {
      await _initializeAndroid();
    }
  }

  Future<void> _initializeAndroid() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) =>
          _openFromPayload(response.payload),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: 'Avisos previos y alertas de vencimiento de tus actividades',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    // App abierta desde una notificación local (mostrada en primer plano).
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _launchItemId = launchDetails?.notificationResponse?.payload;
    }

    if (_pushEnabled) {
      FirebaseMessaging.onMessage.listen(_showForegroundPush);
    }
  }

  /// Devuelve (una sola vez) el id de la actividad que abrió la app.
  String? consumeLaunchItemId() {
    final itemId = _launchItemId;
    _launchItemId = null;
    return (itemId != null && itemId.isNotEmpty) ? itemId : null;
  }

  /// Extrae el id de la actividad de los datos de un push.
  static String? itemIdFromMessage(RemoteMessage message) {
    final rawId = message.data['itemId'] ?? message.data['item_id'];
    final itemId = rawId?.toString();
    return (itemId != null && itemId.isNotEmpty) ? itemId : null;
  }

  /// Solicita permiso para mostrar notificaciones.
  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) return await browser.requestBrowserNotificationPermission();
      if (_isAndroid) {
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        return await androidPlugin?.requestNotificationsPermission() ?? false;
      }
    } catch (e) {
      debugPrint('No se pudo solicitar permiso de notificaciones: $e');
    }
    return false;
  }

  /// Estado del permiso en web: 'granted', 'denied' o 'default'.
  String get webPermissionStatus => browser.browserNotificationPermission;

  // ---------------------------------------------------------------------------
  // Android: push en primer plano
  // ---------------------------------------------------------------------------

  Future<void> _showForegroundPush(RemoteMessage message) async {
    final notification = message.notification;
    final itemId = itemIdFromMessage(message);
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null && body == null) return;

    if (itemId != null) _shownItemIds.add(itemId);
    await _localNotifications.show(
      itemId != null ? _notificationIdFor(itemId) : message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannelId,
          androidChannelName,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: itemId,
    );
  }

  int _notificationIdFor(String itemId) => itemId.hashCode & 0x7fffffff;

  void _openFromPayload(String? itemId) {
    if (itemId == null || itemId.isEmpty) return;
    _onOpenItem?.call(itemId);
  }

  // ---------------------------------------------------------------------------
  // Programación / cancelación
  // ---------------------------------------------------------------------------

  /// Sincroniza los recordatorios con la lista de actividades del usuario.
  ///
  /// Con [replaceAll] se cancelan los recordatorios de actividades que ya no
  /// aparecen en la lista (por ejemplo, eliminadas desde otro dispositivo).
  void syncReminders(List<ActivityItem> items, {bool replaceAll = true}) {
    if (!kIsWeb) return;
    if (replaceAll) {
      final currentIds = items.map((item) => item.id).toSet();
      final staleIds =
          _webTimers.keys.where((id) => !currentIds.contains(id)).toList();
      for (final itemId in staleIds) {
        cancelReminders(itemId);
      }
    }
    for (final item in items) {
      scheduleReminders(item);
    }
  }

  /// (Re)programa los recordatorios de una actividad.
  void scheduleReminders(ActivityItem item) {
    if (!kIsWeb) return;
    _cancelWebTimers(item.id);

    final now = DateTime.now();
    final timers = <Timer>[];
    for (final trigger in ReminderSchedule.buildTriggers(item)) {
      if (_firedTriggerKeys.contains(trigger.key)) continue;
      final delay = trigger.fireAt.difference(now);
      if (delay.isNegative || delay > maxTimerDelay) continue;
      timers.add(Timer(delay, () => _fireTrigger(trigger)));
    }
    if (timers.isNotEmpty) _webTimers[item.id] = timers;
  }

  /// Cancela las notificaciones y alertas pendientes de una actividad
  /// (criterio 4: se llama al completarla o eliminarla).
  void cancelReminders(String itemId) {
    _cancelWebTimers(itemId);
    if (kIsWeb) {
      for (final kind in ReminderKind.values) {
        browser.closeBrowserNotification('${itemId}_${kind.name}');
      }
    }
    if (_isAndroid && _shownItemIds.remove(itemId)) {
      unawaited(_localNotifications.cancel(_notificationIdFor(itemId)));
    }
  }

  /// Cancela todo (por ejemplo, al cerrar sesión).
  void cancelAll() {
    for (final itemId in _webTimers.keys.toList()) {
      cancelReminders(itemId);
    }
    _firedTriggerKeys.clear();
    stopPeriodicSync();
    if (_isAndroid) {
      _shownItemIds.clear();
      unawaited(_localNotifications.cancelAll());
    }
  }

  void _cancelWebTimers(String itemId) {
    final timers = _webTimers.remove(itemId);
    if (timers == null) return;
    for (final timer in timers) {
      timer.cancel();
    }
  }

  void _fireTrigger(ReminderTrigger trigger) {
    _firedTriggerKeys.add(trigger.key);
    _webTimers[trigger.itemId]?.removeWhere((timer) => !timer.isActive);

    browser.showBrowserNotification(
      title: trigger.title,
      body: trigger.body,
      tag: trigger.key,
      onClick: () => _openFromPayload(trigger.itemId),
    );
    _onInAppAlert?.call(trigger);
  }

  // ---------------------------------------------------------------------------
  // Sincronización periódica (web)
  // ---------------------------------------------------------------------------

  /// Vuelve a consultar las actividades periódicamente para detectar las
  /// creadas o modificadas desde otro dispositivo.
  void startPeriodicSync(RefreshCallback refresh) {
    if (!kIsWeb) return;
    stopPeriodicSync();
    _periodicSyncTimer = Timer.periodic(periodicSyncInterval, (_) async {
      try {
        await refresh();
      } catch (e) {
        debugPrint('Error en la sincronización de recordatorios: $e');
      }
    });
  }

  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }
}
