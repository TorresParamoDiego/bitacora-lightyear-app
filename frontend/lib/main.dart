import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/activity_detail_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  // Solicitar permiso para notificaciones.
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  // Escuchar el registro antes de llamar a register().
  messaging.onRegistered.listen(
    (installationId) async {
      debugPrint('✅ EVENTO onRegistered RECIBIDO');
      debugPrint('Tipo: ${installationId.runtimeType}');
      //final user = Supabase.instance.client.auth.currentUser;
      //
      //    if (user == null) {
      //    debugPrint('FID recibido, pero no hay usuario autenticado.');
      //  return;
      //}
      const userId = '00000000-0000-0000-0000-000000000002';
      try {
        await Supabase.instance.client.from('user_fcm_tokens').upsert({
          //'user_id': user.id,
          'user_id': userId,
          'fcm_token': installationId,
          'device_type': 'android',
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'fcm_token');

        debugPrint('FID registrado en Supabase.');
      } catch (e) {
        debugPrint('Error registrando FID: $e');
      }
    },
    onError: (Object error) {
      debugPrint('❌ Error en onRegistered: $error');
    },
  );

  try {
    await messaging.register();
    debugPrint('✅ messaging.register() terminó correctamente');
  } catch (e) {
    debugPrint('No se pudo registrar el dispositivo: $e');
  }

  // Notificación tocada cuando la app estaba en segundo plano.
  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

  // Notificación que abrió la app desde un estado cerrado.
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

  if (itemId == null || itemId.toString().isEmpty) {
    return;
  }

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
      home: const HomeScreen(),
    );
  }
}
