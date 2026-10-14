import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import 'audio_storage_helper.dart';

/// Servicio encargado de la captura de audio utilizando el hardware del dispositivo.
/// 
/// Gestiona permisos nativos y de navegador, la creación de rutas temporales o blobs,
/// y garantiza la compatibilidad del codificador de audio en Android, iOS y Web.
/// Controla el ciclo de vida de la grabación permitiendo iniciar, pausar,
/// reanudar, detener y cancelar.
class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentPath;

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (await hasPermission()) {
      if (kIsWeb) {
        // En Flutter Web no se usa sistema de archivos ni path_provider
        AudioEncoder encoder = AudioEncoder.aacLc;
        if (!await _audioRecorder.isEncoderSupported(encoder)) {
          encoder = AudioEncoder.opus;
        }

        _currentPath = '';
        await _audioRecorder.start(
          RecordConfig(encoder: encoder),
          path: '',
        );
      } else {
        String? dirPath;
        try {
          dirPath = await getTemporaryAudioDirectory();
        } catch (_) {
          dirPath = null;
        }

        if (dirPath == null || dirPath.isEmpty) {
          try {
            dirPath = Directory.systemTemp.path;
          } catch (_) {
            dirPath = '.';
          }
        }

        _currentPath = p.join(dirPath, 'audio_${DateTime.now().millisecondsSinceEpoch}.aac');
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _currentPath!,
        );
      }
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
    try {
      await _audioRecorder.cancel();
    } catch (_) {
      try {
        final path = await _audioRecorder.stop();
        if (path != null && !kIsWeb && path.isNotEmpty) {
          await deleteAudioFile(path);
        }
      } catch (_) {}
    }
    if (_currentPath != null && !kIsWeb && _currentPath!.isNotEmpty) {
      await deleteAudioFile(_currentPath!);
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