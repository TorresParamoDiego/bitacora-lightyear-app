// frontend/lib/services/browser_notifications_stub.dart
//
// Implementación vacía para plataformas no web (Android, escritorio, tests).

bool get isBrowserNotificationSupported => false;

String get browserNotificationPermission => 'denied';

Future<bool> requestBrowserNotificationPermission() async => false;

void showBrowserNotification({
  required String title,
  required String body,
  required String tag,
  required void Function() onClick,
}) {}

void closeBrowserNotification(String tag) {}
