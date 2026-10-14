// frontend/lib/screens/activities_screen.dart
import 'package:flutter/material.dart';
import '../models/activity_item.dart';
import '../services/activities_api_service.dart';

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({Key? key}) : super(key: key);

  @override
  _ActivitiesScreenState createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  final ActivitiesApiService _apiService = ActivitiesApiService();
  late Future<List<ActivityItem>> _futureActivities;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  void _loadActivities() {
    setState(() {
      _futureActivities = _apiService.getActivities();
    });
  }

  String _translateType(String type) {
    switch (type.toLowerCase()) {
      case 'task': return 'Tarea';
      case 'reminder': return 'Recordatorio';
      case 'event': return 'Evento';
      default: return 'Actividad';
    }
  }

  String _translatePriority(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high': return 'Alta';
      case 'medium': return 'Media';
      case 'low': return 'Baja';
      default: return 'Sin prioridad';
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'task': return Icons.check_box_outlined;
      case 'reminder': return Icons.alarm;
      case 'event': return Icons.event;
      default: return Icons.circle_outlined;
    }
  }

  Color _getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high': return Colors.red.shade100;
      case 'medium': return Colors.orange.shade100;
      case 'low': return Colors.green.shade100;
      default: return Colors.grey.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Actividades'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActivities,
          )
        ],
      ),
      body: FutureBuilder<List<ActivityItem>>(
        future: _futureActivities,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('No fue posible recuperar las actividades'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadActivities,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No hay actividades registradas',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_getTypeIcon(item.type), size: 20, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            _translateType(item.type).toUpperCase(),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                          ),
                          const Spacer(),
                          if (item.priority != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getPriorityColor(item.priority),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _translatePriority(item.priority),
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (item.description != null && item.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.description!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item.itemDate != null) ...[
                            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(item.itemDate!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 16),
                          ],
                          if (item.itemTime != null) ...[
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(item.itemTime!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ]
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}