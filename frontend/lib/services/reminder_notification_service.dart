import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/activity_item.dart';
import '../models/notification_preferences.dart';
import 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart'
    as browser;
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
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description:
            'Avisos previos y alertas de vencimiento de tus actividades',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _launchItemId = launchDetails?.notificationResponse?.payload;
    }

    if (_pushEnabled) {
      FirebaseMessaging.onMessage.listen(_showForegroundPush);
    }
  }

  String? consumeLaunchItemId() {
    final itemId = _launchItemId;
    _launchItemId = null;
    return (itemId != null && itemId.isNotEmpty) ? itemId : null;
  }

  static String? itemIdFromMessage(RemoteMessage message) {
    final rawId = message.data['itemId'] ?? message.data['item_id'];
    final itemId = rawId?.toString();
    return (itemId != null && itemId.isNotEmpty) ? itemId : null;
  }

  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) return await browser.requestBrowserNotificationPermission();
      if (_isAndroid) {
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await androidPlugin?.requestNotificationsPermission() ?? false;
      }
    } catch (e) {
      debugPrint('No se pudo solicitar permiso de notificaciones: $e');
    }
    return false;
  }

  String get webPermissionStatus => browser.browserNotificationPermission;

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

  /// Sincroniza los recordatorios web usando los defaults por tipo y offsets personalizados.
  void syncReminders(
    List<ActivityItem> items, {
    bool replaceAll = true,
    TypeNotificationDefaults? defaults,
    Map<String, List<int>> customOffsetsByItemId = const {},
  }) {
    if (!kIsWeb) return;
    if (replaceAll) {
      final currentIds = items.map((item) => item.id).toSet();
      final staleIds = _webTimers.keys
          .where((id) => !currentIds.contains(id))
          .toList();
      for (final itemId in staleIds) {
        cancelReminders(itemId);
      }
    }
    for (final item in items) {
      scheduleReminders(
        item,
        defaults: defaults,
        customOffsets: customOffsetsByItemId[item.id],
      );
    }
  }

  /// Programa los recordatorios de una actividad según sus offsets en minutos (sin horario silencioso).
  void scheduleReminders(
    ActivityItem item, {
    TypeNotificationDefaults? defaults,
    List<int>? customOffsets,
  }) {
    if (!kIsWeb) return;
    _cancelWebTimers(item.id);

    if (item.id.isEmpty || ReminderSchedule.isClosedStatus(item.status)) return;
    final dueAt = TypeNotificationDefaults.resolveDueDateTime(
      itemDate: item.itemDate,
      itemTime: item.itemTime,
    );
    if (dueAt == null) return;

    final effectiveDefaults = defaults ?? TypeNotificationDefaults();
    final offsets = effectiveDefaults.resolveOffsetsForItem(
      itemType: item.type,
      customItemOffsets: customOffsets,
    );

    final now = DateTime.now();
    final timers = <Timer>[];

    // Construye disparadores dinámicos por cada offset en minutos, horas o días.
    for (final offsetMin in offsets) {
      final kind = offsetMin == 0
          ? ReminderKind.due
          : (offsetMin == 1440
                ? ReminderKind.oneDayBefore
                : ReminderKind.thirtyMinutesBefore);
      final triggerKey = '${item.id}_offset_$offsetMin';
      if (_firedTriggerKeys.contains(triggerKey)) continue;

      final fireAt = dueAt.subtract(Duration(minutes: offsetMin));
      if (!fireAt.isAfter(now)) continue;

      final delay = fireAt.difference(now);
      if (delay > maxTimerDelay) continue;

      final trigger = ReminderTrigger(
        itemId: item.id,
        itemTitle: item.title,
        itemType: item.type.toLowerCase(),
        kind: kind,
        fireAt: fireAt,
        dueAt: dueAt,
      );
      timers.add(
        Timer(delay, () {
          _firedTriggerKeys.add(triggerKey);
          _fireTrigger(trigger);
        }),
      );
    }

    if (timers.isNotEmpty) _webTimers[item.id] = timers;
  }

  /// Mantiene compatibilidad de firma y delega en `scheduleReminders` sin horario silencioso.
  void scheduleRemindersWithPrefs(
    ActivityItem item, {
    TypeNotificationDefaults? defaults,
    List<int>? customOffsets,
  }) {
    scheduleReminders(
      item,
      defaults: defaults,
      customOffsets: customOffsets,
    );
  }

  void cancelReminders(String itemId) {
    _cancelWebTimers(itemId);
    if (kIsWeb) {
      for (final kind in ReminderKind.values) {
        browser.closeBrowserNotification('${itemId}_${kind.name}');
      }
    }
    if (_isAndroid) {
      _shownItemIds.remove(itemId);
      unawaited(_localNotifications.cancel(_notificationIdFor(itemId)));
    }
  }

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