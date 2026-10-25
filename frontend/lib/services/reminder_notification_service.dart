import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ReminderNotificationService {
  ReminderNotificationService._();
  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize({void Function(String itemId)? onOpenItem}) async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onOpenItem?.call(payload);
        }
      },
    );

    // Muestra la notificación en pantalla cuando la app está abierta en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'fcm_default_channel',
              'Notificaciones Generales',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          payload: message.data['itemId'],
        );
      }
    });
  }
}