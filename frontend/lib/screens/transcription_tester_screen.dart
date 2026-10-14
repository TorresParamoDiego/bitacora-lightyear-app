import 'package:flutter/material.dart';
import '../services/analysis_api_service.dart';
import 'analysis_review_screen.dart';

/// Pantalla para probar diferentes tipos de transcripciones y verificar
/// la correcta extracción automática de tareas, fechas, eventos y prioridades.
class TranscriptionTesterScreen extends StatefulWidget {
  const TranscriptionTesterScreen({super.key, this.apiService});

  final AnalysisApiService? apiService;

  @override
  State<TranscriptionTesterScreen> createState() => _TranscriptionTesterScreenState();
}

class _TranscriptionTesterScreenState extends State<TranscriptionTesterScreen> {
  final TextEditingController _textController = TextEditingController();
  late final AnalysisApiService _apiService;
  bool _isAnalyzing = false;
  String? _errorMessage;
  String _referenceDate = '2026-10-13';

  static const Color primaryPurple = Color(0xFF5C4EE5);

  final List<Map<String, String>> _presetExamples = [
    {
      'title': 'Ejemplo estándar (Prompt)',
      'subtitle': 'Tarea urgente + Recordatorio + Evento pasado',
      'text':
          'Entregar el proyecto de bases de datos el 17 de octubre, es urgente. '
          'Tener presente el cumpleaños de Ana el 20 de noviembre. '
          'Asistí a clase de natación el 10 de octubre.',
    },
    {
      'title': 'Tarea de alta urgencia con hora',
      'subtitle': 'Prioridad alta + fecha relativa + hora',
      'text': 'Revisar el servidor de producción mañana a las 14:30 lo necesito cuanto antes.',
    },
    {
      'title': 'Tarea de baja prioridad',
      'subtitle': 'Prioridad baja por «cuando se pueda»',
      'text': 'Organizar los archivos antiguos de la oficina cuando se pueda.',
    },
    {
      'title': 'Tarea con prioridad media explícita',
      'subtitle': 'Regla 7: prioridad media sólo si es explícita',
      'text': 'Actualizar las librerías del backend con prioridad media para el 25 de octubre.',
    },
    {
      'title': 'Evento pasado vs Evento futuro',
      'subtitle': 'Regla 9: pasado completed, futuro pending',
      'text': 'Asistí a la conferencia el viernes pasado. Reunión con el decano el próximo viernes.',
    },
    {
      'title': 'Tarea ya completada',
      'subtitle': 'Regla 10: status completed',
      'text': 'Ya entregué el reporte de avance de la materia de software.',
    },
    {
      'title': 'Charla casual sin acciones',
      'subtitle': 'Regla 12: debe devolver 0 elementos',
      'text': 'Hoy fue una mañana muy bonita, desayuné fruta y salí a caminar un rato.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? AnalysisApiService();
    _textController.text = _presetExamples[0]['text']!;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Por favor escribe o selecciona una transcripción.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final items = await _apiService.analyzeTranscription(
        text,
        referenceDate: _referenceDate,
      );

      if (!mounted) return;

      if (items.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Sin elementos detectados'),
            content: const Text(
              'El análisis concluyó correctamente, pero no se identificó ninguna tarea, recordatorio ni evento accionable en este texto (Regla 12).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnalysisReviewScreen(
              initialItems: items,
              rawTranscription: text,
              apiService: _apiService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Pruebas de Análisis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Caja de fecha de referencia
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                color: Colors.white,
                elevation: 0.5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, color: primaryPurple, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Fecha de referencia:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        onPressed: () async {
                          final parsed = DateTime.tryParse(_referenceDate) ?? DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: parsed,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            final m = picked.month.toString().padLeft(2, '0');
                            final d = picked.day.toString().padLeft(2, '0');
                            setState(() => _referenceDate = '${picked.year}-$m-$d');
                          }
                        },
                        child: Text(
                          _referenceDate,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: primaryPurple),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Área de texto de la transcripción
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Colors.white,
                elevation: 0.5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.mic_none, color: primaryPurple, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Texto de la transcripción',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _textController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Ingresa o selecciona una transcripción a analizar...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Botón principal de análisis
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: _isAnalyzing ? null : _runAnalysis,
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  _isAnalyzing ? 'Analizando transcripción...' : 'Analizar Transcripción',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 24),

              // Lista de ejemplos preestablecidos
              const Text(
                'Ejemplos preestablecidos para pruebas',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 10),

              ..._presetExamples.map((ex) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: Colors.white,
                  elevation: 0.5,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    title: Text(
                      ex['title']!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      ex['subtitle']!,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: primaryPurple),
                    onTap: () {
                      _textController.text = ex['text']!;
                      _runAnalysis();
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
