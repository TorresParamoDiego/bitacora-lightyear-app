/// Sesión de usuario activa durante la ejecución de la aplicación.
class AuthSession {
  AuthSession._();
  static String? accessToken;
  static String? userId;
  static bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;
}
