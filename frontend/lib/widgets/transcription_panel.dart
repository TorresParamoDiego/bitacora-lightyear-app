import 'package:flutter/material.dart';
import '../models/transcription_result.dart';
import '../services/transcription_api_service.dart';

/// Widget reutilizable. Pásale la ruta del audio ya grabado por tu pantalla actual.
class TranscriptionPanel extends StatefulWidget {
  const TranscriptionPanel({
    super.key,
    required this.audioPath,
    required this.apiService,
    this.onTranscriptReady,
  });

  final String audioPath;
  final TranscriptionApiService apiService;
  final ValueChanged<String>? onTranscriptReady;

  @override
  State<TranscriptionPanel> createState() => _TranscriptionPanelState();
}

class _TranscriptionPanelState extends State<TranscriptionPanel> {
  bool _loading = false;
  String? _error;
  TranscriptionResult? _result;

  Future<void> _transcribe() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.apiService.transcribeAudio(widget.audioPath);
      if (!mounted) return;
      setState(() => _result = result);
      if (result.completada) widget.onTranscriptReady?.call(result.transcripcion);
    } on TranscriptionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ocurrió un error inesperado. Puedes reintentar.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _transcribe());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(child: Text('Transcribiendo nota de voz…')),
          ]),
        ),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _transcribe,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ]),
        ),
      );
    }

    if (_result != null && !_result!.completada) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_result!.mensaje),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _transcribe,
              icon: const Icon(Icons.refresh),
              label: const Text('Intentar de nuevo'),
            ),
          ]),
        ),
      );
    }

    if (_result?.completada == true) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Transcripción', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(_result!.transcripcion),
          ]),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
