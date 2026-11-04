// frontend/lib/services/activities_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/api_config.dart';
import '../models/activity_item.dart';
import '../models/recording_item.dart'; // Añadir arriba
import 'reminder_notification_service.dart';
import 'reminder_schedule.dart';

class ActivitiesApiService {
  String get _base => ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '');

  ReminderNotificationService get _reminders =>
      ReminderNotificationService.instance;

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
      url += '?recording_id=${Uri.encodeQueryComponent(recordingId)}';
    }

    final response = await http.get(Uri.parse(url), headers: _headers);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(_detail(data, 'No fue posible recuperar las actividades'));
    }
    final items = (data['items'] as List)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // US8: mantener sincronizados los recordatorios con las actividades.
    // Si la lista está filtrada por grabación no se cancelan las demás.
    _reminders.syncReminders(items, replaceAll: recordingId == null);
    return items;
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

  Future<void> updateStatus(ActivityItem item, String status) async {
    // Al completar se marcan todas las banderas como enviadas para que el
    // servidor cancele los push pendientes (criterio 4). Al reabrir sólo se
    // reactivan los avisos cuyo momento aún no ha llegado.
    final payload = <String, dynamic>{
      'status': status,
      ...ReminderSchedule.notificationFlagsFor(
        itemDate: item.itemDate,
        itemTime: item.itemTime,
        status: status,
      ),
    };

    await _send('PUT', '/api/items/${Uri.encodeComponent(item.id)}', payload);
    _rescheduleOrCancel(item.copyWith(status: status));
  }

  Future<void> updateItem(ActivityItem item, Map<String, dynamic> values) async {
    final String? newDate = values['date']?.toString();
    final String? newTime = values['time']?.toString();
    final String newStatus = (values['status'] ?? 'pending').toString();

    // 1. Detectar si la fecha, la hora o el estado fueron modificados
    final bool dateChanged = item.itemDate != newDate;
    final bool timeChanged = item.itemTime != newTime;
    final bool statusChanged = (item.status ?? 'pending') != newStatus;

    final payload = <String, dynamic>{
      'title': values['title'],
      'description': values['description'],
      'type': values['type'],
      'priority': values['priority'],
      'date': newDate,
      'time': newTime,
      'status': newStatus,
    };

    // 2. Si hubo cambio en la programación o el estado, recalcular las banderas
    //    de notificación (sin reactivar avisos cuyo momento ya pasó).
    if (dateChanged || timeChanged || statusChanged) {
      payload.addAll(
        ReminderSchedule.notificationFlagsFor(
          itemDate: newDate,
          itemTime: newTime,
          status: newStatus,
        ),
      );
    }

    await _send('PUT', '/api/items/${Uri.encodeComponent(item.id)}', payload);

    _rescheduleOrCancel(
      ActivityItem(
        id: item.id,
        type: (values['type'] ?? item.type).toString(),
        title: (values['title'] ?? item.title).toString(),
        description: values['description']?.toString(),
        priority: values['priority']?.toString(),
        itemDate: newDate,
        itemTime: newTime,
        status: newStatus,
        sourceExcerpt: item.sourceExcerpt,
      ),
    );
  }

  Future<void> deleteItem(ActivityItem item) async {
    await _send('DELETE', '/api/items/${Uri.encodeComponent(item.id)}');
    _reminders.cancelReminders(item.id);
  }

  void _rescheduleOrCancel(ActivityItem item) {
    if (ReminderSchedule.isClosedStatus(item.status)) {
      _reminders.cancelReminders(item.id);
    } else {
      _reminders.scheduleReminders(item);
    }
  }

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
