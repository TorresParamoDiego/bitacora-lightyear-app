import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Propiedad helper para construir los encabezados con Bearer token
  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<ExtractedItem>> analyzeTranscription(
    String text, {
    String? referenceDate,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];

    final uri = Uri.parse('$_cleanBaseUrl/api/analysis');
    final payload = jsonEncode({
      'text': trimmed,
      if (referenceDate != null && referenceDate.isNotEmpty)
        'reference_date': referenceDate,
    });

    try {
      final response = await _client
          .post(uri, headers: _headers, body: payload)
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
        errorBody ?? 'Error al analizar (${response.statusCode}).',
      );
    } catch (error) {
      throw AnalysisApiException('Error en análisis: $error');
    }
  }

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

        // Adjuntar token al MultipartRequest
        final token = Supabase.instance.client.auth.currentSession?.accessToken;
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }

        final streamed = await _client.send(request).timeout(
          const Duration(seconds: 60),
        );
        response = await http.Response.fromStream(streamed);
      } else {
        response = await _client
            .post(uri, headers: _headers, body: payload)
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
        errorBody ?? 'Error al guardar elementos (${response.statusCode}).',
      );
    } catch (error) {
      throw AnalysisApiException('Error al guardar elementos: $error');
    }
  }

  Future<List<ExtractedItem>> getSavedItems() async {
    final uri = Uri.parse('$_cleanBaseUrl/api/items');

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

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