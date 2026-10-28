import 'package:flutter/material.dart';
import '../models/recording_item.dart';
import '../models/activity_item.dart';
import '../services/activities_api_service.dart';
import 'activity_detail_screen.dart';

class TranscriptionDetailScreen extends StatefulWidget {
  final RecordingItem recording;
  const TranscriptionDetailScreen({super.key, required this.recording});

  @override
  State<TranscriptionDetailScreen> createState() =>
      _TranscriptionDetailScreenState();
}

class _TranscriptionDetailScreenState extends State<TranscriptionDetailScreen> {
  final ActivitiesApiService _apiService = ActivitiesApiService();
  late Future<List<ActivityItem>> _futureActivities;

  @override
  void initState() {
    super.initState();
    _futureActivities = _apiService.getActivities(
      recordingId: widget.recording.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de Transcripción')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: const Color(0xFFEEECFC),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.format_quote, color: Color(0xFF5C4EE5)),
                    SizedBox(width: 8),
                    Text(
                      'Texto extraído:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.recording.transcript ?? 'Sin transcripción.',
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Actividades generadas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ActivityItem>>(
              future: _futureActivities,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No hay actividades de esta grabación.'),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Icon(
                        item.status == 'completed'
                            ? Icons.check_circle
                            : Icons.task_alt,
                        color: item.status == 'completed'
                            ? Colors.green
                            : Colors.blueGrey,
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        item.type.toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ActivityDetailScreen(itemId: item.id),
                          ),
                        ).then(
                          (_) => setState(() {
                            _futureActivities = _apiService.getActivities(
                              recordingId: widget.recording.id,
                            );
                          }),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
