class TranscriptionResult {
  final String estado;
  final String transcripcion;
  final String mensaje;
  final String? idioma;

  const TranscriptionResult({
    required this.estado,
    required this.transcripcion,
    required this.mensaje,
    this.idioma,
  });

  bool get completada => estado == 'completado' && transcripcion.trim().isNotEmpty;

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      estado: (json['estado'] ?? 'sin_voz').toString(),
      transcripcion: (json['transcripcion'] ?? '').toString(),
      mensaje: (json['mensaje'] ?? 'No fue posible transcribir el audio.').toString(),
      idioma: json['idioma']?.toString(),
    );
  }
}
