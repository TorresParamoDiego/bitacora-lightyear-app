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
      id: json['id'] ?? '',
      type: json['type'] ?? 'task',
      title: json['title'] ?? 'Sin título',
      description: json['description'],
      priority: json['priority'],
      itemDate: json['item_date'],
      itemTime: json['item_time'],
      status: json['status'],
    );
  }
}