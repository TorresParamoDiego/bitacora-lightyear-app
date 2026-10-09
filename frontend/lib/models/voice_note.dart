class VoiceNoteResponse {
  final String id;
  final String archivoAudio;
  final String formato;
  final int tamanoBytes;
  final String estado;

  VoiceNoteResponse({
    required this.id,
    required this.archivoAudio,
    required this.formato,
    required this.tamanoBytes,
    required this.estado,
  });

  factory VoiceNoteResponse.fromJson(Map<String, dynamic> json) {
    return VoiceNoteResponse(
      id: json['id'] as String,
      archivoAudio: json['archivo_audio'] as String,
      formato: json['formato'] as String,
      tamanoBytes: json['tamano_bytes'] as int,
      estado: json['estado'] as String,
    );
  }
}