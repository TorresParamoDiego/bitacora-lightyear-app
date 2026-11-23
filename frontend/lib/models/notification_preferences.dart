import 'package:flutter/foundation.dart';

/// Unidades de anticipación soportadas; todas se normalizan a minutos.
enum NotificationUnit {
  minutes('Minutos', 1),
  hours('Horas', 60),
  days('Días', 1440);

  final String label;
  final int minutesMultiplier;
  const NotificationUnit(this.label, this.minutesMultiplier);
}

/// Representa un aviso en minutos antes del vencimiento (`0` = en el momento).
@immutable
class NotificationOffset {
  final int minutes;

  const NotificationOffset(this.minutes);

  factory NotificationOffset.fromValue(int value, NotificationUnit unit) {
    return NotificationOffset(value * unit.minutesMultiplier);
  }

  String formatLabel() {
    if (minutes <= 0) return 'Al momento';
    if (minutes % NotificationUnit.days.minutesMultiplier == 0) {
      final days = minutes ~/ NotificationUnit.days.minutesMultiplier;
      return days == 1 ? '1 día antes' : '$days días antes';
    }
    if (minutes % NotificationUnit.hours.minutesMultiplier == 0) {
      final hours = minutes ~/ NotificationUnit.hours.minutesMultiplier;
      return hours == 1 ? '1 hora antes' : '$hours horas antes';
    }
    return minutes == 1 ? '1 minuto antes' : '$minutes minutos antes';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationOffset && minutes == other.minutes;

  @override
  int get hashCode => minutes.hashCode;
}

/// Esquema default por tipo de actividad (`task`, `reminder`, `event`) y resolución por ítem.
class TypeNotificationDefaults {
  static const int defaultHour = 9;
  static const int defaultMinute = 0;

  final Map<String, List<int>> _byType;

  TypeNotificationDefaults({Map<String, List<int>>? byType})
      : _byType = {
          'task': _normalizeOffsets(byType?['task'] ?? const [1440, 30, 0]),
          'reminder': _normalizeOffsets(byType?['reminder'] ?? const [30, 0]),
          'event': _normalizeOffsets(byType?['event'] ?? const [1440, 60, 0]),
        };

  List<int> offsetsForType(String itemType) {
    final normalized = itemType.trim().toLowerCase();
    return List<int>.unmodifiable(_byType[normalized] ?? _byType['task']!);
  }

  TypeNotificationDefaults withOffsetsForType(
    String itemType,
    List<int> offsets,
  ) {
    final normalized = itemType.trim().toLowerCase();
    final updated = Map<String, List<int>>.from(_byType);
    updated[normalized] = _normalizeOffsets(offsets);
    return TypeNotificationDefaults(byType: updated);
  }

  /// Usa [customItemOffsets] si el ítem tiene configuración propia; si no, aplica el default del tipo.
  List<int> resolveOffsetsForItem({
    required String itemType,
    List<int>? customItemOffsets,
  }) {
    if (customItemOffsets != null) {
      return _normalizeOffsets(customItemOffsets);
    }
    return offsetsForType(itemType);
  }

  /// Combina fecha y hora; si hay fecha sin hora, usa las 09:00 por defecto.
  static DateTime? resolveDueDateTime({String? itemDate, String? itemTime}) {
    if (itemDate == null || itemDate.trim().isEmpty) return null;
    try {
      final datePart = itemDate.trim().split('T').first;
      final dateParts = datePart.split('-');
      if (dateParts.length != 3) return null;
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

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

  // Deduplica, descarta negativos y ordena de mayor a menor anticipación.
  static List<int> _normalizeOffsets(List<int> raw) {
    final cleaned = raw.where((m) => m >= 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return cleaned;
  }
}