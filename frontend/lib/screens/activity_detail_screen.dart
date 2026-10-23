import 'package:flutter/material.dart';
import '../models/activity_item.dart';
import '../services/activities_api_service.dart';

class ActivityDetailScreen extends StatelessWidget {
  final String itemId;
  const ActivityDetailScreen({super.key, required this.itemId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle de actividad')),
    body: FutureBuilder<List<ActivityItem>>(
      future: ActivitiesApiService().getActivities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return const Center(child: Text('No fue posible cargar la actividad.'));
        final matches = (snapshot.data ?? []).where((item) => item.id == itemId);
        if (matches.isEmpty) return const Center(child: Text('La actividad ya no está disponible.'));
        final item = matches.first;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(item.description?.isNotEmpty == true ? item.description! : 'Sin descripción'),
          const SizedBox(height: 12),
          Text('Estado: ${item.status == 'completed' ? 'Completada' : 'Pendiente'}'),
          Text('Fecha: ${item.itemDate ?? 'Sin fecha'}'),
          Text('Hora: ${item.itemTime ?? 'Sin hora'}'),
          Text('Prioridad: ${item.priority ?? 'Sin prioridad'}'),
        ]);
      },
    ),
  );
}
