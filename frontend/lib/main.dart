import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/activities_api_service.dart';
import 'services/auth_service.dart';
import 'services/reminder_notification_service.dart';
import 'services/reminder_schedule.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/activity_detail_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

RemoteMessage? _initialPushMessage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Configuración y Supabase: si fallan se muestra un mensaje en lugar de
  //    dejar la pantalla en blanco.
  try {
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_PUBLISHABLE_KEY'),
    );
  } catch (e, stackTrace) {
    debugPrint('❌ Error inicializando la app: $e\n$stackTrace');
    runApp(StartupErrorApp(errorMessage: e.toString()));
    return;
  }

  // 2. Push (Firebase) sólo en Android. En Web no hay configuración de
  //    Firebase y `Firebase.initializeApp()` lanzaba una excepción que
  //    impedía ejecutar `runApp` (pantalla en blanco).
  final pushEnabled = await _initializePush();

  // 3. Servicio de recordatorios y alertas (US8)
  try {
    await ReminderNotificationService.instance.initialize(
      onOpenItem: openActivityDetail,
      onInAppAlert: _showInAppAlert,
      pushEnabled: pushEnabled,
    );
  } catch (e) {
    debugPrint('❌ Error inicializando notificaciones locales: $e');
  }

  runApp(const BitacoraLightyearApp());

  _listenAuthChanges();

  // 4. Si la app se abrió desde una notificación, ir al detalle.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final pushItemId = _initialPushMessage != null
        ? ReminderNotificationService.itemIdFromMessage(_initialPushMessage!)
        : null;
    final launchItemId =
        pushItemId ?? ReminderNotificationService.instance.consumeLaunchItemId();
    if (launchItemId != null) openActivityDetail(launchItemId);
  });
}

Future<bool> _initializePush() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;

  try {
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

    // Notificación push tocada con la app en segundo plano (criterio 3)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final itemId = ReminderNotificationService.itemIdFromMessage(message);
      if (itemId != null) openActivityDetail(itemId);
    });

    // Notificación push que abrió la app desde cerrada (criterio 3)
    _initialPushMessage = await messaging.getInitialMessage();
    return true;
  } catch (e) {
    debugPrint('❌ No se pudo inicializar Firebase Messaging: $e');
    return false;
  }
}

void _listenAuthChanges() {
  final reminders = ReminderNotificationService.instance;
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    switch (data.event) {
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
        if (data.session != null) {
          unawaited(_refreshReminders());
          reminders.startPeriodicSync(_refreshReminders);
        }
        break;
      case AuthChangeEvent.signedOut:
        reminders.cancelAll();
        break;
      default:
        break;
    }
  });
}

/// En Web consulta las actividades para (re)programar las alertas locales.
/// En Android no es necesario: los push los envía el servidor.
Future<void> _refreshReminders() async {
  if (!kIsWeb) return;
  if (Supabase.instance.client.auth.currentSession == null) return;
  try {
    await ActivitiesApiService().getActivities();
  } catch (e) {
    debugPrint('No se pudieron sincronizar los recordatorios: $e');
  }
}

/// Abre el detalle de una actividad (criterio 3).
void openActivityDetail(String itemId) {
  if (itemId.isEmpty) return;
  if (Supabase.instance.client.auth.currentSession == null) return;

  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openActivityDetail(itemId));
    return;
  }
  navigator.push(
    MaterialPageRoute(
      builder: (_) => ActivityDetailScreen(itemId: itemId),
    ),
  );
}

/// Alerta dentro de la app cuando se cumple un recordatorio (Web).
/// Al vencer se muestra un diálogo (alerta inmediata, criterio 2); para los
/// avisos previos basta con un SnackBar.
void _showInAppAlert(ReminderTrigger trigger) {
  final overlayContext = appNavigatorKey.currentState?.overlay?.context;

  if (trigger.isDueAlert && overlayContext != null) {
    showDialog<void>(
      context: overlayContext,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.alarm, color: Colors.red, size: 40),
        title: Text(trigger.title),
        content: Text(trigger.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openActivityDetail(trigger.itemId);
            },
            child: const Text('Ver detalle'),
          ),
        ],
      ),
    );
    return;
  }

  appScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 10),
      content: Text('${trigger.title}\n${trigger.body}'),
      action: SnackBarAction(
        label: 'Ver',
        onPressed: () => openActivityDetail(trigger.itemId),
      ),
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
      scaffoldMessengerKey: appScaffoldMessengerKey,
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

/// Pantalla mostrada cuando falla la configuración inicial (p. ej. falta el .env).
class StartupErrorApp extends StatelessWidget {
  final String errorMessage;
  const StartupErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'No fue posible iniciar la aplicación',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verifica que el archivo frontend/.env exista y tenga '
                  'SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
