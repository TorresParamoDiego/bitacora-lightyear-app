class ApiConfig {
  static const String baseUrl = 'http://192.168.1.73:8000'; //si usan el telefono es la ip de su computadora, si usan emulador es la ip del emulador

  static String get transcriptionEndpoint => '$baseUrl/api/transcriptions';
  static String get uploadEndpoint => '$baseUrl/voice/upload';
  static String get healthEndpoint => '$baseUrl/health';
}