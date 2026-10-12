class ApiConfig {
  static const String baseUrl = 'https://bitacora-lightyear-app.onrender.com'; //si usan el telefono es la ip de su computadora, si usan emulador es la ip del emulador

  static String get transcriptionEndpoint => '$baseUrl/api/transcriptions';
  static String get uploadEndpoint => '$baseUrl/voice/upload';
  static String get healthEndpoint => '$baseUrl/health';
}