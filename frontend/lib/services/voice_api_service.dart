import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import '../models/voice_note.dart';
/// Servicio de red responsable de la comunicación con la API de FastAPI.
/// 
/// Encapsula la lógica para enviar el archivo de audio local al servidor
/// mediante una petición HTTP [multipart/form-data] en el campo requerido 'file'.
/// Captura y mapea los códigos de estado del servidor (201, 400, 413, 415)
/// hacia excepciones legibles por la UI.
class VoiceApiService {
  Future<VoiceNoteResponse> uploadVoiceNote(String filePath) async {
    final uri = Uri.parse(ApiConfig.uploadEndpoint);
    
    // El backend espera un form-data, usamos MultipartRequest
    final request = http.MultipartRequest('POST', uri);

    // El campo requerido por tu backend FastAPI es exactamente 'file'
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

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
      throw Exception('Fallo de conexión. Verifica que ambos dispositivos estén en la misma red y el servidor activo.');
    }
  }
}