// frontend/lib/models/activity_item.dart

class ActivityItem {
  final String id;
  final String type;
  final String title;
  final String? description;
  final String? priority;
  final String? itemDate;
  final String? itemTime;
  final String? status;

  ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.priority,
    this.itemDate,
    this.itemTime,
    this.status,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'task').toString(),
      title: (json['title'] ?? 'Sin título').toString(),
      description: json['description']?.toString(),
      priority: json['priority']?.toString(),
      itemDate: (json['date'] ?? json['item_date'])?.toString(),
      itemTime: (json['time'] ?? json['item_time'])?.toString(),
      status: json['status']?.toString(),
    );
  }
}