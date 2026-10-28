// frontend/lib/services/activities_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/api_config.dart';
import '../models/activity_item.dart';
import '../models/recording_item.dart'; // Añadir arriba
class ActivitiesApiService {
  String get _base => ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '');

  // Extrae el token JWT directamente de la sesión activa en Supabase
  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<RecordingItem>> getRecordings() async {
    final response = await http.get(Uri.parse('$_base/voice/recordings'), headers: _headers);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(_detail(data, 'No fue posible recuperar las transcripciones'));
    }
    return (data['recordings'] as List)
        .map((e) => RecordingItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  Future<List<ActivityItem>> getActivities({String? recordingId}) async {
    String url = '$_base/api/items';
    if (recordingId != null) {
      url += '?recording_id=$recordingId';
    }
    
    final response = await http.get(Uri.parse(url), headers: _headers);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(_detail(data, 'No fue posible recuperar las actividades'));
    }
    return (data['items'] as List)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Crea una nueva actividad formateando el cuerpo como exige `SaveItemsRequest` ({ "items": [...] })
  Future<void> createItem(Map<String, dynamic> values) {
    final singleItem = {
      'type': values['type'],
      'title': values['title'],
      'description': values['description'] ?? values['title'],
      'priority': values['priority'],
      'date': values['date'],
      'time': values['time'],
      'status': values['status'] ?? 'pending',
    };

    final payload = {
      'items': [singleItem],
    };

    return _send('POST', '/api/items', payload);
  }

  Future<void> updateStatus(ActivityItem item, String status) => _send(
    'PATCH',
    '/api/items/${Uri.encodeComponent(item.id)}/status',
    {'status': status},
  );

  Future<void> updateItem(ActivityItem item, Map<String, dynamic> values) {
    // 1. Detectar si la fecha o la hora fueron modificadas
    final bool dateChanged = item.itemDate != values['date'];
    final bool timeChanged = item.itemTime != values['time'];

    final payload = <String, dynamic>{
      'title': values['title'],
      'description': values['description'],
      'type': values['type'],
      'priority': values['priority'],
      'date': values['date'],
      'time': values['time'],
      'status': values['status'] ?? 'pending',
    };

    // 2. Si hubo cambio en la programación, reiniciar las banderas de notificación
    if (dateChanged || timeChanged) {
      payload['notification_1d_sent'] = false;
      payload['notification_30m_sent'] = false;
      payload['notification_due_sent'] = false;
    }

    return _send('PUT', '/api/items/${Uri.encodeComponent(item.id)}', payload);
  }

  Future<void> deleteItem(ActivityItem item) =>
      _send('DELETE', '/api/items/${Uri.encodeComponent(item.id)}');

  Future<void> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$_base$path');
    late http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(
          uri,
          headers: _headers,
          body: json.encode(body),
        );
        break;
      case 'PATCH':
        response = await http.patch(
          uri,
          headers: _headers,
          body: json.encode(body),
        );
        break;
      case 'PUT':
        response = await http.put(
          uri,
          headers: _headers,
          body: json.encode(body),
        );
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: _headers);
        break;
      default:
        throw Exception('Operación no soportada');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic data;
      try {
        data = json.decode(utf8.decode(response.bodyBytes));
      } catch (_) {}
      throw Exception(_detail(data, 'No fue posible completar la operación'));
    }
  }

  String _detail(dynamic data, String fallback) =>
      data is Map && data['detail'] != null
      ? data['detail'].toString()
      : fallback;
  
}
