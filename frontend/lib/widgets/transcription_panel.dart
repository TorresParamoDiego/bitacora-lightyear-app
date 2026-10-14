import 'package:flutter/material.dart';
import '../models/transcription_result.dart';
import '../services/transcription_api_service.dart';
import '../services/analysis_api_service.dart';
import '../screens/analysis_review_screen.dart';

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Transcripción', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Icon(Icons.check_circle, color: Color(0xFF2ECC71), size: 20),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _result!.transcripcion,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C4EE5),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.white),
            label: Text(
              _isAnalyzing ? 'Analizando con IA...' : 'Analizar tareas y eventos',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _isAnalyzing ? null : _analyzeContent,
          ),
          if (_analysisError != null) ...[
            const SizedBox(height: 10),
            Text(
              _analysisError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }

  bool _isAnalyzing = false;
  String? _analysisError;

  Future<void> _analyzeContent() async {
    final transcript = _result?.transcripcion.trim();
    if (transcript == null || transcript.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });

    try {
      final analysisService = AnalysisApiService();
      final items = await analysisService.analyzeTranscription(transcript);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AnalysisReviewScreen(
            initialItems: items,
            rawTranscription: transcript,
            audioPath: widget.audioPath,
            apiService: analysisService,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _analysisError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }
}
