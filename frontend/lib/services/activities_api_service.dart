import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import '../models/activity_item.dart';
import 'auth_session.dart';

class ActivitiesApiService {
  String get _base => ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '');
  Map<String, String> get _headers => {'Content-Type': 'application/json; charset=utf-8', if (AuthSession.isAuthenticated) 'Authorization': 'Bearer ${AuthSession.accessToken}'};

  Future<List<ActivityItem>> getActivities() async {
    final response = await http.get(Uri.parse('$_base/api/items'), headers: _headers);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) throw Exception(_detail(data, 'No fue posible recuperar las actividades'));
    if (data is! Map<String, dynamic> || data['items'] is! List) throw const FormatException('Respuesta de actividades inválida');
    return (data['items'] as List).map((e) => ActivityItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateStatus(ActivityItem item, String status) => _send('PATCH', '/api/items/${Uri.encodeComponent(item.id)}/status', {'status': status});
  Future<void> updateItem(ActivityItem item, Map<String, dynamic> values) => _send('PUT', '/api/items/${Uri.encodeComponent(item.id)}', values);
  Future<void> deleteItem(ActivityItem item) => _send('DELETE', '/api/items/${Uri.encodeComponent(item.id)}');

  Future<void> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$_base$path');
    late http.Response response;
    switch (method) {
      case 'PATCH': response = await http.patch(uri, headers: _headers, body: json.encode(body)); break;
      case 'PUT': response = await http.put(uri, headers: _headers, body: json.encode(body)); break;
      case 'DELETE': response = await http.delete(uri, headers: _headers); break;
      default: throw Exception('Operación no soportada');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic data; try { data = json.decode(utf8.decode(response.bodyBytes)); } catch (_) {}
      throw Exception(_detail(data, 'No fue posible completar la operación'));
    }
  }

  String _detail(dynamic data, String fallback) => data is Map && data['detail'] != null ? data['detail'].toString() : fallback;
}
