import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/api_config.dart';
import '../models/transcription_result.dart';
import 'audio_upload_helper.dart';

class TranscriptionApiService {
  TranscriptionApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<TranscriptionResult> transcribeAudio(String audioPath) async {
    final exists = await checkFileExists(audioPath);
    if (!exists) {
      throw const TranscriptionException('No se encontró el archivo de audio.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}/api/transcriptions'),
    );

    // Inyección de Token JWT para autenticación en FastAPI
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(
      await createMultipartFileFromAudio('audio', audioPath, defaultFileName: 'audio.aac'),
    );

    try {
      final streamed = await _client.send(request).timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const TranscriptionException('El servidor devolvió una respuesta no válida.');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return TranscriptionResult.fromJson(body);
      }
      final detail = body['detail'] ?? body['mensaje'] ?? body['error'];
      throw TranscriptionException(
        detail?.toString() ?? 'Error de transcripción (${response.statusCode}).',
      );
    } on SocketException {
      throw const TranscriptionException('No hay conexión con el servidor.');
    } on http.ClientException {
      throw const TranscriptionException('Fallo de red al intentar transcribir.');
    } catch (error) {
      rethrow;
    }
  }

  void close() => _client.close();
}

class TranscriptionException implements Exception {
  const TranscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}