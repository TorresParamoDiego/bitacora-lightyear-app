import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/home_screen.dart';
import 'screens/activity_detail_screen.dart';
import 'services/reminder_notification_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BitacoraLightyearApp());
  if (!kIsWeb) {
    ReminderNotificationService.instance.initialize(onOpenItem: (itemId) {
      appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ActivityDetailScreen(itemId: itemId)));
    });
  }
}

class BitacoraLightyearApp extends StatelessWidget {
  const BitacoraLightyearApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: appNavigatorKey,
    title: 'Bitácora Lightyear',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C4EE5), primary: const Color(0xFF5C4EE5), secondary: const Color(0xFF2ECC71), tertiary: const Color(0xFF3498DB),), useMaterial3: true),
    home: const HomeScreen(),
  );
}
