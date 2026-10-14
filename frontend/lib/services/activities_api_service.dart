// frontend/lib/services/activities_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import '../models/activity_item.dart';

class ActivitiesApiService {
  Future<List<ActivityItem>> getActivities() async {
    final baseUrl = ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final url = Uri.parse('$baseUrl/api/items');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decodedData = json.decode(utf8.decode(response.bodyBytes)); // Manejo de acentos
        if (decodedData is! Map<String, dynamic> ||
            decodedData['items'] is! List) {
          throw const FormatException(
            'La respuesta no contiene una lista de actividades.',
          );
        }
        final List<dynamic> itemsJson = decodedData['items'] ?? [];
        return itemsJson.map((json) => ActivityItem.fromJson(json)).toList();
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('No fue posible recuperar las actividades: $e');
    }
  }
}