import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import '../models/extracted_item.dart';
import 'audio_upload_helper.dart';

class AnalysisApiException implements Exception {
  const AnalysisApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AnalysisApiService {
  AnalysisApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  String get _cleanBaseUrl => baseUrl.replaceFirst(RegExp(r'/$'), '');

  /// Envía la transcripción al backend para extraer tareas, eventos y recordatorios.
  Future<List<ExtractedItem>> analyzeTranscription(
    String text, {
    String? referenceDate,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    final uri = Uri.parse('$_cleanBaseUrl/api/analysis');
    final payload = jsonEncode({
      'text': trimmed,
      if (referenceDate != null && referenceDate.isNotEmpty)
        'reference_date': referenceDate,
    });

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['items'] is List) {
          final list = decoded['items'] as List;
          return list
              .whereType<Map<String, dynamic>>()
              .map((item) => ExtractedItem.fromJson(item))
              .toList();
        }
        return [];
      }

      final errorBody = _parseError(response.body);
      throw AnalysisApiException(
        errorBody ?? 'Error en el servidor al analizar (${response.statusCode}).',
      );
    } on SocketException {
      throw const AnalysisApiException(
        'No hay conexión con el servidor. Verifica que el backend esté activo.',
      );
    } on http.ClientException {
      throw const AnalysisApiException(
        'Fallo de conexión. Verifica la IP del servidor o la conexión de red.',
      );
    } on FormatException {
      throw const AnalysisApiException(
        'La respuesta del servidor no tiene un formato JSON válido.',
      );
    } on AnalysisApiException {
      rethrow;
    } catch (error) {
      if (error.toString().contains('TimeoutException')) {
        throw const AnalysisApiException(
          'El análisis tardó demasiado tiempo. Puedes reintentar.',
        );
      }
      throw AnalysisApiException('Error inesperado: $error');
    }
  }

  /// Guarda los elementos confirmados por el usuario a través del backend.
  Future<int> saveConfirmedItems(
    List<ExtractedItem> items, {
    String? audioPath,
    String? userId,
    String? recordingId,
    bool simulateError = false,
  }) async {
    if (items.isEmpty) return 0;

    final path = audioPath;
    final hasAudio = path != null && path.isNotEmpty;
    final uri = Uri.parse(
      '$_cleanBaseUrl/api/items${hasAudio ? '/with-audio' : ''}',
    );

    final payload = jsonEncode({
      'items': items.map((i) => i.toJson()).toList(),
      if (userId != null) 'user_id': userId,
      if (recordingId != null) 'recording_id': recordingId,
      'simulate_error': simulateError,
    });

    try {
      late final http.Response response;

      if (hasAudio) {
        final request = http.MultipartRequest('POST', uri)
          ..fields['items'] = payload
          ..files.add(await createMultipartFileFromAudio(
            'audio',
            path,
            defaultFileName: 'audio.aac',
          ));
        final streamed = await _client.send(request).timeout(
          const Duration(seconds: 60),
        );
        response = await http.Response.fromStream(streamed);
      } else {
        response = await _client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(const Duration(seconds: 30));
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['saved_count'] != null) {
          return (decoded['saved_count'] as num).toInt();
        }
        return items.length;
      }

      final errorBody = _parseError(response.body);
      throw AnalysisApiException(
        errorBody ?? 'Error al guardar los elementos (${response.statusCode}).',
      );
    } on SocketException {
      throw const AnalysisApiException(
        'No hay conexión con el backend para guardar los elementos.',
      );
    } on http.ClientException {
      throw const AnalysisApiException(
        'Fallo de red al intentar guardar los elementos.',
      );
    } on AnalysisApiException {
      rethrow;
    } catch (error) {
      throw AnalysisApiException('Error al guardar elementos: $error');
    }
  }

  /// Recupera los elementos guardados previamente en el backend.
  Future<List<ExtractedItem>> getSavedItems() async {
    final uri = Uri.parse('$_cleanBaseUrl/api/items');

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['items'] is List) {
          return (decoded['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map((i) => ExtractedItem.fromJson(i))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  String? _parseError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['detail'] ?? decoded['message'] ?? decoded['mensaje'])?.toString();
      }
    } catch (_) {}
    return null;
  }

  void close() => _client.close();
}
