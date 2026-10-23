class ApiConfig {
  /// URL del backend desplegado en Render
  static const String renderUrl = 'https://bitacora-lightyear-app.onrender.com';

  /// URLs para pruebas en servidor local si fuera necesario:
  /// - Web / Windows: 'http://127.0.0.1:8000'
  /// - Emulador Android: 'http://10.0.2.2:8000'
  /// - Teléfono en red local: 'http://192.168.1.11:8000'
  static const String localUrl = 'http://127.0.0.1:8000';

  /// URL activa de la API. Conectada a Render por defecto.
  static String baseUrl = localUrl;

  static String get transcriptionEndpoint => '$baseUrl/api/transcriptions';
  static String get uploadEndpoint => '$baseUrl/voice/upload';
  static String get healthEndpoint => '$baseUrl/health';
  static String get analysisEndpoint => '$baseUrl/api/analysis';
  static String get itemsEndpoint => '$baseUrl/api/items';
}