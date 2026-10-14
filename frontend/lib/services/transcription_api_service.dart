import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import '../models/transcription_result.dart';

class TranscriptionApiService {
  TranscriptionApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<TranscriptionResult> transcribeAudio(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw const TranscriptionException('No se encontró el archivo de audio.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}/api/transcriptions'),
    );
    request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

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
      throw const TranscriptionException('No hay conexión con el servidor. Revisa que el backend esté activo.');
    } on HttpException {
      throw const TranscriptionException('Ocurrió un problema al enviar el audio.');
    } on http.ClientException {
      throw const TranscriptionException('No hay conexión con el servidor. Revisa la IP y que el backend esté activo.');
    } on FormatException {
      throw const TranscriptionException('La respuesta del servidor no tiene un formato válido.');
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      if (error.toString().contains('TimeoutException')) {
        throw const TranscriptionException('La transcripción tardó demasiado. Puedes reintentar.');
      }
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
