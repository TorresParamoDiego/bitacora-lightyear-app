import 'dart:io';
import 'package:http/http.dart' as http;

Future<http.MultipartFile> createMultipartFileFromAudio(String fieldName, String path, {String? defaultFileName}) async {
  if (path.startsWith('blob:') || path.startsWith('http://') || path.startsWith('https://')) {
    final response = await http.get(Uri.parse(path));
    return http.MultipartFile.fromBytes(
      fieldName,
      response.bodyBytes,
      filename: defaultFileName ?? 'audio.aac',
    );
  }
  return await http.MultipartFile.fromPath(
    fieldName,
    path,
    filename: defaultFileName,
  );
}

Future<bool> checkFileExists(String path) async {
  if (path.startsWith('blob:') || path.startsWith('http://') || path.startsWith('https://')) {
    return true;
  }
  return await File(path).exists();
}
