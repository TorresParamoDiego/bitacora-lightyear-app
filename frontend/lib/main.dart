import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/activity_detail_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.get('SUPABASE_URL'),
    publishableKey: dotenv.get('SUPABASE_PUBLISHABLE_KEY'),
  );

  await Firebase.initializeApp();

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Escuchar refrescos de token FCM para el usuario actual
  messaging.onTokenRefresh.listen((newToken) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await AuthService().registerFcmToken();
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  final initialMessage = await messaging.getInitialMessage();

  runApp(const BitacoraLightyearApp());

  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(initialMessage);
    });
  }
}

void _handleNotificationTap(RemoteMessage message) {
  final itemId = message.data['itemId'];
  if (itemId == null || itemId.toString().isEmpty) return;

  appNavigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => ActivityDetailScreen(itemId: itemId.toString()),
    ),
  );
}

class BitacoraLightyearApp extends StatelessWidget {
  const BitacoraLightyearApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Evaluar si ya existe una sesión persistente guardada en el dispositivo
    final session = Supabase.instance.client.auth.currentSession;

    // Sincronizar el token si el usuario ya viene autenticado
    if (session != null) {
      AuthService().registerFcmToken();
    }

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Bitácora Lightyear',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C4EE5),
          primary: const Color(0xFF5C4EE5),
          secondary: const Color(0xFF2ECC71),
          tertiary: const Color(0xFF3498DB),
        ),
        useMaterial3: true,
      ),
      // Si la sesión existe, va directo a HomeScreen; de lo contrario a LoginScreen
      home: session != null ? const HomeScreen() : const LoginScreen(),
    );
  }
}