// frontend/lib/services/reminder_schedule.dart
//
// Lógica pura (sin dependencias de plataforma) para calcular cuándo deben
// dispararse los recordatorios y alertas de vencimiento de una actividad (US8).
//
// Los tiempos previos coinciden con los del proceso de push del servidor
// (columnas notification_1d_sent / notification_30m_sent / notification_due_sent).
import '../models/activity_item.dart';

/// Tipo de disparo de un recordatorio.
enum ReminderKind { oneDayBefore, thirtyMinutesBefore, due }

/// Un disparo concreto (fecha/hora) de recordatorio para una actividad.
class ReminderTrigger {
  final String itemId;
  final String itemTitle;
  final String itemType;
  final ReminderKind kind;
  final DateTime fireAt;
  final DateTime dueAt;

  const ReminderTrigger({
    required this.itemId,
    required this.itemTitle,
    required this.itemType,
    required this.kind,
    required this.fireAt,
    required this.dueAt,
  });

  /// Clave única por actividad + tipo de disparo.
  String get key => '${itemId}_${kind.name}';

  bool get isDueAlert => kind == ReminderKind.due;

  String get title {
    final typeLabel = ReminderSchedule.typeLabel(itemType);
    switch (kind) {
      case ReminderKind.oneDayBefore:
        return 'Recordatorio: $typeLabel para mañana';
      case ReminderKind.thirtyMinutesBefore:
        return 'Recordatorio: faltan 30 minutos';
      case ReminderKind.due:
        return itemType == 'event'
            ? '¡Tu evento comienza ahora!'
            : '¡$typeLabel vencida!';
    }
  }

  String get body {
    final timeText = ReminderSchedule.formatTime(dueAt);
    final dateText = ReminderSchedule.formatDate(dueAt);
    final verb = itemType == 'event' ? 'comienza' : 'vence';
    switch (kind) {
      case ReminderKind.oneDayBefore:
        return '"$itemTitle" $verb el $dateText a las $timeText.';
      case ReminderKind.thirtyMinutesBefore:
        return '"$itemTitle" $verb hoy a las $timeText.';
      case ReminderKind.due:
        return 'La fecha límite de "$itemTitle" se cumplió ($dateText $timeText).';
    }
  }
}

class ReminderSchedule {
  ReminderSchedule._();

  static const Duration oneDayLead = Duration(days: 1);
  static const Duration thirtyMinutesLead = Duration(minutes: 30);

  /// Hora usada cuando la actividad sólo tiene fecha (igual que en el detalle).
  static const int defaultHour = 9;
  static const int defaultMinute = 0;

  static Duration leadFor(ReminderKind kind) => switch (kind) {
        ReminderKind.oneDayBefore => oneDayLead,
        ReminderKind.thirtyMinutesBefore => thirtyMinutesLead,
        ReminderKind.due => Duration.zero,
      };

  /// Nombre de la columna en la tabla `items` que marca el disparo como enviado.
  static String flagColumnFor(ReminderKind kind) => switch (kind) {
        ReminderKind.oneDayBefore => 'notification_1d_sent',
        ReminderKind.thirtyMinutesBefore => 'notification_30m_sent',
        ReminderKind.due => 'notification_due_sent',
      };

  static bool isClosedStatus(String? status) {
    final normalized = status?.toLowerCase();
    return normalized == 'completed' || normalized == 'cancelled';
  }

  /// Fecha/hora límite (hora local) de una actividad o `null` si no tiene fecha.
  static DateTime? dueDateTimeOf({String? itemDate, String? itemTime}) {
    if (itemDate == null || itemDate.trim().isEmpty) return null;
    try {
      final dateParts = itemDate.trim().split('-');
      if (dateParts.length != 3) return null;
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2].split('T').first);

      var hour = defaultHour;
      var minute = defaultMinute;
      if (itemTime != null && itemTime.trim().isNotEmpty) {
        final timeParts = itemTime.trim().split(':');
        if (timeParts.length >= 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
        }
      }
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  /// Todos los disparos (pasados y futuros) de una actividad pendiente con fecha.
  static List<ReminderTrigger> buildTriggers(ActivityItem item) {
    if (item.id.isEmpty || isClosedStatus(item.status)) return const [];
    final dueAt = dueDateTimeOf(itemDate: item.itemDate, itemTime: item.itemTime);
    if (dueAt == null) return const [];

    return ReminderKind.values
        .map(
          (kind) => ReminderTrigger(
            itemId: item.id,
            itemTitle: item.title,
            itemType: item.type.toLowerCase(),
            kind: kind,
            fireAt: dueAt.subtract(leadFor(kind)),
            dueAt: dueAt,
          ),
        )
        .toList();
  }

  /// Calcula las banderas de notificación que deben guardarse en el servidor.
  ///
  /// - Actividad completada/cancelada: todas en `true` → el servidor ya no
  ///   enviará push pendientes (criterio 4).
  /// - Actividad pendiente: `true` sólo para disparos cuyo momento ya pasó
  ///   (evita push atrasados), `false` para los futuros.
  static Map<String, bool> notificationFlagsFor({
    String? itemDate,
    String? itemTime,
    String? status,
    DateTime? now,
  }) {
    final closed = isClosedStatus(status);
    final dueAt = dueDateTimeOf(itemDate: itemDate, itemTime: itemTime);
    final currentTime = now ?? DateTime.now();

    return {
      for (final kind in ReminderKind.values)
        flagColumnFor(kind): closed ||
            (dueAt != null && !dueAt.subtract(leadFor(kind)).isAfter(currentTime)),
    };
  }

  static String typeLabel(String type) => switch (type.toLowerCase()) {
        'event' => 'Evento',
        'reminder' => 'Recordatorio',
        _ => 'Tarea',
      };

  static String formatTime(DateTime dateTime) =>
      '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';

  static String formatDate(DateTime dateTime) =>
      '${_twoDigits(dateTime.day)}/${_twoDigits(dateTime.month)}/${dateTime.year}';

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
// En frontend/lib/services/reminder_schedule.dart
class NotificationPrefs {
  final bool enabled;
  final int quietStartHour;
  final int quietEndHour;
  final bool muteQuietHours;

  const NotificationPrefs({
    this.enabled = true,
    this.quietStartHour = 22,
    this.quietEndHour = 7,
    this.muteQuietHours = true,
  });

  /// Ajusta una hora de disparo si cae dentro de la ventana silenciosa nocturna.
  DateTime applyQuietHours(DateTime candidate) {
    if (!muteQuietHours || quietStartHour == quietEndHour) return candidate;

    final wrapsMidnight = quietStartHour > quietEndHour;
    final inQuiet = wrapsMidnight
        ? (candidate.hour >= quietStartHour || candidate.hour < quietEndHour)
        : (candidate.hour >= quietStartHour && candidate.hour < quietEndHour);

    if (!inQuiet) return candidate;

    var targetDate = DateTime(candidate.year, candidate.month, candidate.day);
    if (wrapsMidnight && candidate.hour >= quietStartHour) {
      targetDate = targetDate.add(const Duration(days: 1));
    }
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      quietEndHour,
      0,
    );
  }
}