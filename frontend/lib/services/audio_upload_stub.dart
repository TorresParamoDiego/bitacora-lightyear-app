import 'package:http/http.dart' as http;

Future<http.MultipartFile> createMultipartFileFromAudio(String fieldName, String path, {String? defaultFileName}) async {
  // En Web o URLs de blob, leemos los bytes a través de http.get
  final response = await http.get(Uri.parse(path));
  return http.MultipartFile.fromBytes(
    fieldName,
    response.bodyBytes,
    filename: defaultFileName ?? 'audio.aac',
  );
}

Future<bool> checkFileExists(String path) async {
  return true;
}
