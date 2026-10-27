import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/api_config.dart';
import '../models/voice_note.dart';
import 'audio_upload_helper.dart';

class VoiceApiService {
  Future<VoiceNoteResponse> uploadVoiceNote(String filePath) async {
    final uri = Uri.parse(ApiConfig.uploadEndpoint);
    final request = http.MultipartRequest('POST', uri);

    // Inyección de Token JWT para autenticación en FastAPI
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(
      await createMultipartFileFromAudio('file', filePath, defaultFileName: 'audio.aac'),
    );

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        return VoiceNoteResponse.fromJson(data);
      } else if (response.statusCode == 400) {
        throw Exception('Solicitud inválida o archivo vacío.');
      } else if (response.statusCode == 413) {
        throw Exception('El archivo supera el límite de 25 MB.');
      } else if (response.statusCode == 415) {
        throw Exception('Formato de audio no permitido.');
      } else {
        throw Exception('Error del servidor: código ${response.statusCode}');
      }
    } on Exception catch (e) {
      if (e.toString().startsWith('Exception: ') && e is! http.ClientException) rethrow;
      throw Exception('Fallo de conexión. Verifica la IP del servidor.');
    }
  }
}