import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Registrar Token FCM en Supabase para el usuario autenticado
  Future<void> registerFcmToken() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _supabase.from('user_fcm_tokens').upsert({
          'user_id': user.id,
          'fcm_token': fcmToken,
          'device_type': defaultTargetPlatform.name.toLowerCase(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'fcm_token');
        debugPrint('✅ FCM Token registrado para el usuario: ${user.id}');
      }
    } catch (e) {
      debugPrint('❌ Error registrando FCM Token: $e');
    }
  }

  // Eliminar Token FCM de Supabase al cerrar sesión
  Future<void> removeFcmToken() async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _supabase
            .from('user_fcm_tokens')
            .delete()
            .eq('fcm_token', fcmToken);
        debugPrint('🗑️ FCM Token removido de Supabase.');
      }
    } catch (e) {
      debugPrint('❌ Error eliminando FCM Token: $e');
    }
  }

  // Inicio de Sesión
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.session != null) {
      await registerFcmToken();
    }
    return response;
  }

  // Registro con inicio automático
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );

    // Como confirm_email está desactivado, Supabase inicia sesión inmediatamente
    if (response.session != null) {
      await registerFcmToken();
    }
    return response;
  }

  // Cierre de Sesión Manual
  Future<void> signOut() async {
    await removeFcmToken();
    await _supabase.auth.signOut();
  }
}