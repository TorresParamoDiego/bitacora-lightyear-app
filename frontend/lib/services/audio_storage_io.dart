import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> getTemporaryAudioDirectory() async {
  try {
    final dir = await getTemporaryDirectory();
    return dir.path;
  } catch (_) {
    try {
      return Directory.systemTemp.path;
    } catch (_) {
      return null;
    }
  }
}

Future<void> deleteAudioFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
