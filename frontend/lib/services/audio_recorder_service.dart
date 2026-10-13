import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
/// Servicio encargado de la captura de audio utilizando el hardware del dispositivo.
/// 
/// Gestiona permisos nativos, la creación de rutas temporales y garantiza que la
/// compresión de audio sea en formato AAC-LC. Controla el ciclo de vida de la grabación
/// permitiendo iniciar, pausar (durante alertas de seguridad), reanudar, detener y
/// cancelar (destruyendo el archivo temporal).

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentPath;

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (await hasPermission()) {
      final dir = await getTemporaryDirectory();
      // Usamos AAC como está configurado en tu backend
      _currentPath = p.join(dir.path, 'audio_${DateTime.now().millisecondsSinceEpoch}.aac');
      
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _currentPath!,
      );
    } else {
      throw Exception('Permiso de micrófono denegado');
    }
  }

  // Detiene y conserva el archivo
  Future<String?> stopRecording() async {
    final path = await _audioRecorder.stop();
    return path;
  }

  // Detiene y elimina el archivo
  Future<void> cancelRecording() async {
    final path = await _audioRecorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentPath = null;
  }

  void dispose() {
    _audioRecorder.dispose();
  }
  Future<void> pauseRecording() async {
    await _audioRecorder.pause();
  }

  Future<void> resumeRecording() async {
    await _audioRecorder.resume();
  }
}