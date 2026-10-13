import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> getTemporaryAudioDirectory() async {
  final dir = await getTemporaryDirectory();
  return dir.path;
}

Future<void> deleteAudioFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
