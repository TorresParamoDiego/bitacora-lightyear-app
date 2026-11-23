import '../models/notification_preferences.dart';

/// Calcula el momento efectivo de disparo aplicando anticipación en minutos
/// (sin horario silencioso) y respetando estados cerrados.
class NotificationPlanner {
  static DateTime? computeTriggerTime({
    required DateTime scheduledAt,
    required int offsetMinutes,
    required String status,
    bool notificationsEnabled = true,
    bool skipCompletedOrCancelled = true,
  }) {
    if (!notificationsEnabled || offsetMinutes < 0) return null;

    final normalizedStatus = status.trim().toLowerCase();
    if (skipCompletedOrCancelled &&
        (normalizedStatus == 'completed' || normalizedStatus == 'cancelled')) {
      return null;
    }

    return scheduledAt.subtract(Duration(minutes: offsetMinutes));
  }

  /// Resuelve la lista de instantes de disparo para una actividad usando su
  /// configuración personalizada o el esquema default del tipo.
  static List<DateTime> computeTriggersForItem({
    required String itemType,
    required String status,
    String? itemDate,
    String? itemTime,
    List<int>? customItemOffsets,
    TypeNotificationDefaults? defaults,
    bool notificationsEnabled = true,
    bool skipCompletedOrCancelled = true,
  }) {
    final dueAt = TypeNotificationDefaults.resolveDueDateTime(
      itemDate: itemDate,
      itemTime: itemTime,
    );
    if (dueAt == null) return const [];

    final effectiveDefaults = defaults ?? TypeNotificationDefaults();
    final offsets = effectiveDefaults.resolveOffsetsForItem(
      itemType: itemType,
      customItemOffsets: customItemOffsets,
    );

    final triggers = <DateTime>[];
    for (final offset in offsets) {
      final fireAt = computeTriggerTime(
        scheduledAt: dueAt,
        offsetMinutes: offset,
        status: status,
        notificationsEnabled: notificationsEnabled,
        skipCompletedOrCancelled: skipCompletedOrCancelled,
      );
      if (fireAt != null) {
        triggers.add(fireAt);
      }
    }
    return triggers;
  }
}