import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_item.dart';
import '../models/notification_preferences.dart';

/// Gestiona en Supabase los defaults por tipo de actividad y los avisos
/// programados (`offset_minutes`) de cada ítem.
class NotificationScheduleService {
  NotificationScheduleService._();
  static final NotificationScheduleService instance =
      NotificationScheduleService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Obtiene el `public.users.id` correspondiente al usuario autenticado actual.
  /// Devuelve `null` si no hay sesión o el usuario público aún no existe.
  Future<String?> _resolvePublicUserId() async {
    final authUser = _supabase.auth.currentUser;
    if (authUser == null) return null;

    final row = await _supabase
        .from('users')
        .select('id')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();

    final id = row?['id']?.toString();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Carga el esquema default por tipo (`task`, `reminder`, `event`) del usuario.
  Future<TypeNotificationDefaults> loadTypeDefaults() async {
    try {
      final userId = await _resolvePublicUserId();
      if (userId == null) return TypeNotificationDefaults();

      final rows = await _supabase
          .from('user_notification_type_defaults')
          .select('item_type, offset_minutes')
          .eq('user_id', userId);

      final map = <String, List<int>>{};
      for (final raw in (rows as List)) {
        if (raw is! Map<String, dynamic>) continue;
        final itemType = raw['item_type']?.toString().toLowerCase();
        final rawOffsets = raw['offset_minutes'];
        if (itemType == null || rawOffsets is! List) continue;
        map[itemType] = rawOffsets
            .map((e) => (e as num).toInt())
            .where((m) => m >= 0)
            .toList();
      }
      return TypeNotificationDefaults(byType: map);
    } catch (e) {
      debugPrint('⚠️ Error cargando defaults de notificación por tipo: $e');
      return TypeNotificationDefaults();
    }
  }

  /// Guarda o actualiza los minutos de anticipación default para un tipo de actividad.
  Future<void> saveTypeDefault({
    required String itemType,
    required List<int> offsetMinutes,
  }) async {
    final userId = await _resolvePublicUserId();
    if (userId == null) {
      throw StateError('No hay sesión activa o perfil de usuario público.');
    }

    final normalizedType = itemType.trim().toLowerCase();
    final cleaned = offsetMinutes.where((m) => m >= 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    await _supabase.from('user_notification_type_defaults').upsert(
      {
        'user_id': userId,
        'item_type': normalizedType,
        'offset_minutes': cleaned,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,item_type',
    );
  }

  /// Consulta los `offset_minutes` configurados para un ítem específico.
  /// Devuelve `null` si el ítem no tiene filas propias (para usar el default del tipo).
  Future<List<int>?> getOffsetsForItem(String itemId) async {
    if (itemId.isEmpty) return null;
    try {
      final rows = await _supabase
          .from('item_notification_schedules')
          .select('offset_minutes')
          .eq('item_id', itemId);

      final list = rows as List;
      if (list.isEmpty) return null;

      final offsets = list
          .whereType<Map<String, dynamic>>()
          .map((r) => (r['offset_minutes'] as num).toInt())
          .where((m) => m >= 0)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

      return offsets;
    } catch (e) {
      debugPrint('⚠️ Error leyendo schedules del ítem $itemId:$e');
      return null;
    }
  }

  /// Carga en una sola consulta todos los `offset_minutes` agrupados por `item_id`.
  Future<Map<String, List<int>>> loadCustomOffsetsByItemIds(
    List<String> itemIds,
  ) async {
    final validIds = itemIds.where((id) => id.isNotEmpty).toSet().toList();
    if (validIds.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from('item_notification_schedules')
          .select('item_id, offset_minutes')
          .inFilter('item_id', validIds);

      final grouped = <String, Set<int>>{};
      for (final raw in (rows as List).whereType<Map<String, dynamic>>()) {
        final itemId = raw['item_id']?.toString();
        final offset = (raw['offset_minutes'] as num?)?.toInt();
        if (itemId == null || itemId.isEmpty || offset == null || offset < 0) {
          continue;
        }
        grouped.putIfAbsent(itemId, () => <int>{}).add(offset);
      }

      return grouped.map(
        (key, values) => MapEntry(
          key,
          values.toList()..sort((a, b) => b.compareTo(a)),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error cargando batch de schedules: $e');
      return const {};
    }
  }

  /// Sincroniza los avisos de una actividad en `item_notification_schedules`.
  /// Conserva `sent = true` si el mismo `offset_minutes` ya había sido enviado.
  Future<void> syncItemSchedules({
    required ActivityItem item,
    TypeNotificationDefaults? defaults,
    List<int>? customOffsets,
  }) async {
    if (item.id.isEmpty) return;

    final userId = await _resolvePublicUserId();
    if (userId == null) return;

    final status = (item.status ?? 'pending').trim().toLowerCase();
    final isClosed = status == 'completed' || status == 'cancelled';
    final dueAt = TypeNotificationDefaults.resolveDueDateTime(
      itemDate: item.itemDate,
      itemTime: item.itemTime,
    );

    // Si está cerrada o sin fecha, se eliminan programaciones pendientes para evitar disparos.
    if (isClosed || dueAt == null) {
      await _supabase
          .from('item_notification_schedules')
          .delete()
          .eq('item_id', item.id)
          .eq('user_id', userId);
      return;
    }

    final effectiveDefaults = defaults ?? await loadTypeDefaults();
    final targetOffsets = effectiveDefaults.resolveOffsetsForItem(
      itemType: item.type,
      customItemOffsets: customOffsets,
    );

    final existingRows = await _supabase
        .from('item_notification_schedules')
        .select('offset_minutes, sent, sent_at')
        .eq('item_id', item.id)
        .eq('user_id', userId);

    final alreadySentByOffset = <int, Map<String, dynamic>>{};
    for (final raw in (existingRows as List)) {
      if (raw is! Map<String, dynamic>) continue;
      final off = (raw['offset_minutes'] as num).toInt();
      if (raw['sent'] == true) {
        alreadySentByOffset[off] = raw;
      }
    }

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final nowLocal = DateTime.now();

    // Reemplaza la programación del ítem para reflejar exactamente los offsets elegidos.
    await _supabase
        .from('item_notification_schedules')
        .delete()
        .eq('item_id', item.id)
        .eq('user_id', userId);

    if (targetOffsets.isEmpty) return;

    final rowsToInsert = targetOffsets.map((offsetMin) {
      final fireAt = dueAt.subtract(Duration(minutes: offsetMin));
      final prevSent = alreadySentByOffset[offsetMin];
      final markSent = prevSent != null || !fireAt.isAfter(nowLocal);

      return {
        'item_id': item.id,
        'user_id': userId,
        'offset_minutes': offsetMin,
        'sent': markSent,
        'sent_at': prevSent?['sent_at'] ?? (markSent ? nowUtc : null),
        'updated_at': nowUtc,
      };
    }).toList();

    await _supabase.from('item_notification_schedules').insert(rowsToInsert);
  }

  /// Elimina todos los avisos programados de una actividad al borrarla.
  Future<void> deleteItemSchedules(String itemId) async {
    if (itemId.isEmpty) return;
    try {
      await _supabase
          .from('item_notification_schedules')
          .delete()
          .eq('item_id', itemId);
    } catch (e) {
      debugPrint('⚠️ Error eliminando schedules del ítem $itemId:$e');
    }
  }
}