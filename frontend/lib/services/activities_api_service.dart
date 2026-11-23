import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/api_config.dart';
import '../models/activity_item.dart';
import '../models/notification_preferences.dart';
import '../models/recording_item.dart';
import 'notification_schedule_service.dart';
import 'reminder_notification_service.dart';
import 'reminder_schedule.dart';

class ActivitiesApiService {
  String get _base => ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '');

  ReminderNotificationService get _reminders =>
      ReminderNotificationService.instance;

  NotificationScheduleService get _scheduleService =>
      NotificationScheduleService.instance;

  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<RecordingItem>> getRecordings() async {
    final response = await http.get(
      Uri.parse('$_base/voice/recordings'),
      headers: _headers,
    );
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(
        _detail(data, 'No fue posible recuperar las transcripciones'),
      );
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
      throw Exception(
        _detail(data, 'No fue posible recuperar las actividades'),
      );
    }
    final items = (data['items'] as List)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // Carga defaults por tipo y offsets personalizados en batch para no sobrescribir timers.
    final defaults = await _scheduleService.loadTypeDefaults();
    final customByItemId = await _scheduleService.loadCustomOffsetsByItemIds(
      items.map((e) => e.id).toList(),
    );

    // Garantiza que ítems activos con fecha que aún no tengan filas en BD reciban su default.
    for (final item in items) {
      if (item.id.isEmpty || customByItemId.containsKey(item.id)) continue;
      if (ReminderSchedule.isClosedStatus(item.status)) continue;
      if (item.itemDate == null || item.itemDate!.trim().isEmpty) continue;
      try {
        await _scheduleService.syncItemSchedules(
          item: item,
          defaults: defaults,
        );
      } catch (e) {
        debugPrint('⚠️ Error inicializando schedules por defecto para ${item.id}: $e');
      }
    }

    _reminders.syncReminders(
      items,
      replaceAll: recordingId == null,
      defaults: defaults,
      customOffsetsByItemId: customByItemId,
    );
    return items;
  }

  /// Crea una actividad y sincroniza sus offsets personalizados o default en BD y Web.
  Future<void> createItem(
    Map<String, dynamic> values, {
    List<int>? customOffsets,
  }) async {
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

    final responseBody = await _send('POST', '/api/items', payload);

    String? createdId = values['id']?.toString();
    if ((createdId == null || createdId.isEmpty) && responseBody is Map) {
      final rawItems = responseBody['items'];
      if (rawItems is List && rawItems.isNotEmpty && rawItems.first is Map) {
        createdId = (rawItems.first as Map)['id']?.toString();
      } else if (responseBody['id'] != null) {
        createdId = responseBody['id']?.toString();
      }
    }

    if (createdId != null && createdId.isNotEmpty) {
      final createdItem = ActivityItem(
        id: createdId,
        type: (values['type'] ?? 'task').toString(),
        title: (values['title'] ?? '').toString(),
        description: values['description']?.toString(),
        priority: values['priority']?.toString(),
        itemDate: values['date']?.toString(),
        itemTime: values['time']?.toString(),
        status: (values['status'] ?? 'pending').toString(),
      );
      try {
        final defaults = await _scheduleService.loadTypeDefaults();
        await _scheduleService.syncItemSchedules(
          item: createdItem,
          defaults: defaults,
          customOffsets: customOffsets,
        );
        _reminders.scheduleReminders(
          createdItem,
          defaults: defaults,
          customOffsets: customOffsets,
        );
      } catch (e) {
        debugPrint('⚠️ No se pudo sincronizar programación inicial: $e');
      }
    } else if (customOffsets != null) {
      // Si el backend no devolvió el ID directamente, lo resuelve por coincidencia reciente.
      try {
        final latest = await getActivities();
        final match = latest.firstWhere(
          (it) =>
              it.title == values['title']?.toString() &&
              it.type == values['type']?.toString() &&
              it.itemDate == values['date']?.toString(),
          orElse: () => ActivityItem(
            id: '',
            type: (values['type'] ?? 'task').toString(),
            title: (values['title'] ?? '').toString(),
          ),
        );
        if (match.id.isNotEmpty) {
          final defaults = await _scheduleService.loadTypeDefaults();
          await _scheduleService.syncItemSchedules(
            item: match,
            defaults: defaults,
            customOffsets: customOffsets,
          );
          _reminders.scheduleReminders(
            match,
            defaults: defaults,
            customOffsets: customOffsets,
          );
        }
      } catch (e) {
        debugPrint('⚠️ No se pudo enlazar offsets al ítem recién creado: $e');
      }
    }
  }

  Future<void> updateStatus(ActivityItem item, String status) async {
    final payload = <String, dynamic>{
      'status': status,
      ...ReminderSchedule.notificationFlagsFor(
        itemDate: item.itemDate,
        itemTime: item.itemTime,
        status: status,
      ),
    };

    await _send('PUT', '/api/items/${Uri.encodeComponent(item.id)}', payload);
    final updatedItem = item.copyWith(status: status);

    try {
      final defaults = await _scheduleService.loadTypeDefaults();
      final existingOffsets = await _scheduleService.getOffsetsForItem(item.id);
      await _scheduleService.syncItemSchedules(
        item: updatedItem,
        defaults: defaults,
        customOffsets: existingOffsets,
      );
      if (ReminderSchedule.isClosedStatus(updatedItem.status)) {
        _reminders.cancelReminders(updatedItem.id);
      } else {
        _reminders.scheduleReminders(
          updatedItem,
          defaults: defaults,
          customOffsets: existingOffsets,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error sincronizando schedules tras cambio de estado: $e');
      _rescheduleOrCancel(updatedItem);
    }
  }

  Future<void> updateItem(
    ActivityItem item,
    Map<String, dynamic> values, {
    List<int>? customOffsets,
  }) async {
    final String? newDate = values['date']?.toString();
    final String? newTime = values['time']?.toString();
    final String newStatus = (values['status'] ?? 'pending').toString();

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

    final updatedItem = ActivityItem(
      id: item.id,
      type: (values['type'] ?? item.type).toString(),
      title: (values['title'] ?? item.title).toString(),
      description: values['description']?.toString(),
      priority: values['priority']?.toString(),
      itemDate: newDate,
      itemTime: newTime,
      status: newStatus,
      sourceExcerpt: item.sourceExcerpt,
    );

    try {
      final defaults = await _scheduleService.loadTypeDefaults();
      final effectiveOffsets =
          customOffsets ?? await _scheduleService.getOffsetsForItem(item.id);
      await _scheduleService.syncItemSchedules(
        item: updatedItem,
        defaults: defaults,
        customOffsets: effectiveOffsets,
      );
      if (ReminderSchedule.isClosedStatus(updatedItem.status)) {
        _reminders.cancelReminders(updatedItem.id);
      } else {
        _reminders.scheduleReminders(
          updatedItem,
          defaults: defaults,
          customOffsets: effectiveOffsets,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error sincronizando schedules al editar ítem: $e');
      _rescheduleOrCancel(updatedItem);
    }
  }

  Future<void> deleteItem(ActivityItem item) async {
    await _send('DELETE', '/api/items/${Uri.encodeComponent(item.id)}');
    await _scheduleService.deleteItemSchedules(item.id);
    _reminders.cancelReminders(item.id);
  }

  void _rescheduleOrCancel(ActivityItem item) {
    if (ReminderSchedule.isClosedStatus(item.status)) {
      _reminders.cancelReminders(item.id);
    } else {
      _reminders.scheduleReminders(item);
    }
  }

  Future<dynamic> _send(
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

    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = json.decode(utf8.decode(response.bodyBytes));
      } catch (_) {}
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_detail(data, 'No fue posible completar la operación'));
    }
    return data;
  }

  String _detail(dynamic data, String fallback) =>
      data is Map && data['detail'] != null
      ? data['detail'].toString()
      : fallback;
}