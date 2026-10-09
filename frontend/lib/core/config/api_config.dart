class ApiConfig {
  static const String baseUrl = 'http://192.168.100.59:8000'; //si usan el telefono es la ip de su computadora, si usan emulador es la ip del emulador

  static String get uploadEndpoint => '$baseUrl/voice/upload';
  static String get healthEndpoint => '$baseUrl/health';
}