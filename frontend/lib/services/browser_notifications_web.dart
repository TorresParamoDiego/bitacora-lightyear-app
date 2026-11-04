// frontend/lib/services/browser_notifications_web.dart
//
// Notificaciones nativas del navegador (Web Notifications API) para la versión
// web de la app. Se usan para los recordatorios y alertas de vencimiento (US8).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

final Map<String, web.Notification> _openNotifications = {};

bool get isBrowserNotificationSupported =>
    globalContext.has('Notification');

String get browserNotificationPermission =>
    isBrowserNotificationSupported ? web.Notification.permission : 'denied';

Future<bool> requestBrowserNotificationPermission() async {
  if (!isBrowserNotificationSupported) return false;
  if (web.Notification.permission == 'granted') return true;
  if (web.Notification.permission == 'denied') return false;
  final result = await web.Notification.requestPermission().toDart;
  return result.toDart == 'granted';
}

void showBrowserNotification({
  required String title,
  required String body,
  required String tag,
  required void Function() onClick,
}) {
  if (!isBrowserNotificationSupported ||
      web.Notification.permission != 'granted') {
    return;
  }

  closeBrowserNotification(tag);
  final notification = web.Notification(
    title,
    web.NotificationOptions(
      body: body,
      tag: tag,
      icon: 'icons/Icon-192.png',
      requireInteraction: true,
    ),
  );

  notification.onclick = ((web.Event event) {
    event.preventDefault();
    web.window.focus();
    notification.close();
    _openNotifications.remove(tag);
    onClick();
  }).toJS;

  _openNotifications[tag] = notification;
}

void closeBrowserNotification(String tag) {
  _openNotifications.remove(tag)?.close();
}
