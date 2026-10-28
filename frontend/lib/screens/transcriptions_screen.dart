import 'package:flutter/material.dart';
import '../models/recording_item.dart';
import '../services/activities_api_service.dart';
import 'transcription_detail_screen.dart';
import 'user_profile_screen.dart';

class TranscriptionsScreen extends StatefulWidget {
  const TranscriptionsScreen({super.key});

  @override
  State<TranscriptionsScreen> createState() => _TranscriptionsScreenState();
}

class _TranscriptionsScreenState extends State<TranscriptionsScreen> {
  final ActivitiesApiService _apiService = ActivitiesApiService();
  late Future<List<RecordingItem>> _futureRecordings;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  void _loadRecordings() {
    setState(() {
      _futureRecordings = _apiService.getRecordings();
    });
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'Fecha desconocida';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Notas de Voz'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserProfileScreen()),
                );
              },
              child: const CircleAvatar(
                backgroundColor: Color(0xFF5C4EE5),
                radius: 18,
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<RecordingItem>>(
        future: _futureRecordings,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || (snapshot.data ?? []).isEmpty) {
            return const Center(
              child: Text('No hay transcripciones disponibles'),
            );
          }

          final recordings = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: recordings.length,
            itemBuilder: (context, index) {
              final rec = recordings[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEEECFC),
                    child: Icon(Icons.mic, color: Color(0xFF5C4EE5)),
                  ),
                  title: Text(
                    rec.transcript?.isNotEmpty == true
                        ? rec.transcript!
                        : 'Audio sin transcribir',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    _formatDate(rec.createdAt),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TranscriptionDetailScreen(recording: rec),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
