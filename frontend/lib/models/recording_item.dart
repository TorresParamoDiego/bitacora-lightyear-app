class RecordingItem {
  final String id;
  final String? originalFilename;
  final String? transcript;
  final String? createdAt;
  final int? durationSeconds;

  RecordingItem({
    required this.id,
    this.originalFilename,
    this.transcript,
    this.createdAt,
    this.durationSeconds,
  });

  factory RecordingItem.fromJson(Map<String, dynamic> json) {
    return RecordingItem(
      id: json['id'].toString(),
      originalFilename: json['original_filename']?.toString(),
      transcript: json['transcript']?.toString(),
      createdAt: json['created_at']?.toString(),
      durationSeconds: json['duration_seconds'] as int?,
    );
  }
}