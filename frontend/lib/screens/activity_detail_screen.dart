import 'package:flutter/material.dart';
import '../models/activity_item.dart';
import '../services/activities_api_service.dart';

class ActivityDetailScreen extends StatefulWidget {
  final String itemId;
  const ActivityDetailScreen({super.key, required this.itemId});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  final ActivitiesApiService _apiService = ActivitiesApiService();
  late Future<List<ActivityItem>> _futureActivities;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _futureActivities = _apiService.getActivities();
    });
  }

  Future<void> _toggleStatus(ActivityItem item) async {
    final newStatus = item.status?.toLowerCase() == 'completed' ? 'pending' : 'completed';
    setState(() => _busy = true);
    try {
      await _apiService.updateStatus(item, newStatus);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'completed'
                ? 'Actividad marcada como completada'
                : 'Actividad marcada como pendiente',
          ),
        ),
      );
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _typeColor(String type) => switch (type.toLowerCase()) {
        'event' => Colors.purple,
        'reminder' => Colors.green,
        'task' => Colors.blue,
        _ => Colors.grey
      };

  Color _priorityColor(String? p) => switch (p?.toLowerCase()) {
        'high' => Colors.red,
        'medium' => Colors.orange,
        'low' => Colors.blue,
        _ => Colors.grey
      };

  String _typeLabel(String type) => switch (type.toLowerCase()) {
        'task' => 'Tarea',
        'reminder' => 'Recordatorio',
        'event' => 'Evento',
        _ => 'Actividad'
      };

  String _priorityLabel(String? p) => switch (p?.toLowerCase()) {
        'high' => 'Alta',
        'medium' => 'Media',
        'low' => 'Baja',
        _ => 'Sin prioridad'
      };

  bool _isOverdue(ActivityItem item) {
    if (item.status?.toLowerCase() == 'completed') return false;
    if (item.itemDate == null || item.itemDate!.isEmpty) return false;
    try {
      final dateParts = item.itemDate!.split('-');
      if (dateParts.length != 3) return false;
      int year = int.parse(dateParts[0]);
      int month = int.parse(dateParts[1]);
      int day = int.parse(dateParts[2]);

      int hour = 9;
      int minute = 0;
      if (item.itemTime != null && item.itemTime!.trim().isNotEmpty) {
        final timeParts = item.itemTime!.split(':');
        if (timeParts.length >= 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
        }
      }
      return DateTime(year, month, day, hour, minute).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de actividad'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<List<ActivityItem>>(
            future: _futureActivities,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      const Text('No fue posible cargar la actividad.'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }

              final matches = (snapshot.data ?? []).where((item) => item.id == widget.itemId);
              if (matches.isEmpty) {
                return const Center(
                  child: Text('La actividad ya no está disponible o fue eliminada.'),
                );
              }

              final item = matches.first;
              final completed = item.status?.toLowerCase() == 'completed';
              final overdue = _isOverdue(item);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badges de Tipo, Prioridad y Vencimiento
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _typeColor(item.type).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _typeColor(item.type), width: 0.8),
                          ),
                          child: Text(
                            _typeLabel(item.type),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _typeColor(item.type),
                            ),
                          ),
                        ),
                        if (item.priority != null && item.priority!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _priorityColor(item.priority).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _priorityColor(item.priority), width: 0.8),
                            ),
                            child: Text(
                              _priorityLabel(item.priority),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _priorityColor(item.priority),
                              ),
                            ),
                          ),
                        if (overdue)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red, width: 0.8),
                            ),
                            child: const Text(
                              'Vencida',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Título de la actividad
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            decoration: completed ? TextDecoration.lineThrough : null,
                            color: overdue ? Colors.red.shade900 : null,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Tarjeta de Descripción
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Descripción',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.description?.isNotEmpty == true
                                    ? item.description!
                                    : 'Sin descripción adicional.',
                                style: const TextStyle(fontSize: 15, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Información Programada
                    ListTile(
                      leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                      title: const Text('Fecha asignada'),
                      subtitle: Text(item.itemDate ?? 'Sin fecha asignada'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time, color: Colors.blueGrey),
                      title: const Text('Hora asignada'),
                      subtitle: Text(item.itemTime ?? 'Sin hora asignada (09:00 AM por defecto)'),
                    ),
                    ListTile(
                      leading: Icon(
                        completed ? Icons.check_circle : Icons.pending,
                        color: completed ? Colors.green : Colors.orange,
                      ),
                      title: const Text('Estatus'),
                      subtitle: Text(completed ? 'Completada' : 'Pendiente'),
                    ),
                    const SizedBox(height: 24),

                    // Botón principal para cambiar estatus
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: completed ? Colors.orange : Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(completed ? Icons.undo : Icons.check),
                        label: Text(
                          completed ? 'Marcar como pendiente' : 'Marcar como completada',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _toggleStatus(item),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_busy)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}