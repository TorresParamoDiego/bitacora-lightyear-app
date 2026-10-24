import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/activity_item.dart';

/// Recordatorios locales del dispositivo.
class ReminderNotificationService {
  ReminderNotificationService._();
  static final ReminderNotificationService instance =
      ReminderNotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize({void Function(String itemId)? onOpenItem}) async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final dynamic timezoneResult = await FlutterTimezone.getLocalTimezone();
      // Convierte el resultado a String sin importar la versión exacta del paquete
      final String timeZoneName = timezoneResult.toString();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onOpenItem?.call(payload);
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  int _id(String itemId, int suffix) => (itemId.hashCode ^ suffix) & 0x7fffffff;

  Future<void> sync(List<ActivityItem> items) async {
    await initialize();

    for (final item in items) {
      final baseId = _id(item.id, 1);
      final dueId = _id(item.id, 2);
      final due = _dateTime(item.itemDate, item.itemTime);

      if (item.status?.toLowerCase() == 'completed' ||
          due == null ||
          !due.isAfter(DateTime.now())) {
        await _plugin.cancel(baseId);
        await _plugin.cancel(dueId);
        continue;
      }

      // Recordatorio 15 minutos antes
      final reminder = due.subtract(const Duration(minutes: 15));
      if (reminder.isAfter(DateTime.now())) {
        // Corrección 2: Eliminado uiLocalNotificationDateInterpretation que ya no existe en v17+
        await _plugin.zonedSchedule(
          baseId,
          'Recordatorio de actividad',
          item.title,
          tz.TZDateTime.from(reminder, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminders',
              'Recordatorios',
              channelDescription: 'Avisos previos de actividades',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: item.id,
        );
      } else {
        await _plugin.cancel(baseId);
      }

      // Alerta al vencer
      await _plugin.zonedSchedule(
        dueId,
        'Actividad vencida',
        'La actividad "${item.title}" llegó a su fecha límite.',
        tz.TZDateTime.from(due, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_due',
            'Vencimientos',
            channelDescription: 'Alertas de vencimiento de actividades',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: item.id,
      );
    }
  }

  Future<void> cancelForItem(String itemId) async {
    await _plugin.cancel(_id(itemId, 1));
    await _plugin.cancel(_id(itemId, 2));
  }

  DateTime? _dateTime(String? date, String? time) {
    if (date == null || date.isEmpty) return null;
    try {
      final timeStr = (time != null && time.isNotEmpty) ? time : '23:59';
      final parts = timeStr.split(':');
      final hh = parts[0].padLeft(2, '0');
      final mm = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
      return DateTime.parse('${date}T$hh:$mm:00');
    } catch (_) {
      return null;
    }
  }
}