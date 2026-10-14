/// Modelo que representa un elemento extraído de una transcripción.
/// 
/// Todos los campos están definidos de acuerdo al estándar:
/// - [type]: 'task', 'reminder' o 'event'.
/// - [title]: título breve y descriptivo.
/// - [description]: detalles relevantes de la transcripción.
/// - [priority]: 'high', 'medium', 'low' o null.
/// - [date]: fecha en formato 'YYYY-MM-DD' o null.
/// - [time]: hora en formato 'HH:mm' o null.
/// - [status]: 'pending', 'completed' o 'cancelled'.
class ExtractedItem {
  ExtractedItem({
    required this.type,
    required this.title,
    required this.description,
    this.priority,
    this.date,
    this.time,
    this.status = 'pending',
  });

  final String type;
  final String title;
  final String description;
  final String? priority;
  final String? date;
  final String? time;
  final String status;

  bool get isTask => type == 'task';
  bool get isReminder => type == 'reminder';
  bool get isEvent => type == 'event';

  String get typeLabel {
    switch (type) {
      case 'task':
        return 'Tarea';
      case 'reminder':
        return 'Recordatorio';
      case 'event':
        return 'Evento';
      default:
        return 'Elemento';
    }
  }

  String? get priorityLabel {
    switch (priority) {
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Media';
      case 'low':
        return 'Baja';
      default:
        return null;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'completed':
        return isTask ? 'Completada' : 'Completado';
      case 'cancelled':
        return isTask ? 'Cancelada' : 'Cancelado';
      case 'pending':
      default:
        return 'Pendiente';
    }
  }

  /// Formatea la fecha ISO a texto legible en español si es válida.
  String? get formattedDate {
    if (date == null || date!.isEmpty) return null;
    try {
      final parts = date!.split('-');
      if (parts.length == 3) {
        final year = parts[0];
        final month = int.tryParse(parts[1]) ?? 1;
        final day = int.tryParse(parts[2]) ?? 1;
        const monthNames = [
          'ene', 'feb', 'mar', 'abr', 'may', 'jun',
          'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
        ];
        final monthStr = (month >= 1 && month <= 12) ? monthNames[month - 1] : parts[1];
        return '$day $monthStr $year';
      }
    } catch (_) {}
    return date;
  }

  factory ExtractedItem.fromJson(Map<String, dynamic> json) {
    String cleanString(dynamic val, {String fallback = ''}) {
      if (val == null) return fallback;
      final str = val.toString().trim();
      return (str == 'null' || str == 'None') ? fallback : str;
    }

    String? cleanNullableString(dynamic val) {
      if (val == null) return null;
      final str = val.toString().trim();
      if (str.isEmpty || str == 'null' || str == 'None') return null;
      return str;
    }

    final rawType = cleanString(json['type'], fallback: 'task').toLowerCase();
    final validType = (rawType == 'reminder' || rawType == 'event') ? rawType : 'task';

    final rawPriority = cleanNullableString(json['priority'])?.toLowerCase();
    String? validPriority;
    if (rawPriority == 'high' || rawPriority == 'medium' || rawPriority == 'low') {
      validPriority = rawPriority;
    }

    final rawStatus = cleanString(json['status'], fallback: 'pending').toLowerCase();
    String validStatus = 'pending';
    if (rawStatus == 'completed' || rawStatus == 'cancelled') {
      validStatus = rawStatus;
    }

    return ExtractedItem(
      type: validType,
      title: cleanString(json['title'], fallback: 'Sin título'),
      description: cleanString(json['description']),
      priority: validPriority,
      date: cleanNullableString(json['date']),
      time: cleanNullableString(json['time']),
      status: validStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'title': title,
      'description': description,
      'priority': priority,
      'date': date,
      'time': time,
      'status': status,
    };
  }

  ExtractedItem copyWith({
    String? type,
    String? title,
    String? description,
    String? Function()? priority,
    String? Function()? date,
    String? Function()? time,
    String? status,
  }) {
    return ExtractedItem(
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority != null ? priority() : this.priority,
      date: date != null ? date() : this.date,
      time: time != null ? time() : this.time,
      status: status ?? this.status,
    );
  }
}
