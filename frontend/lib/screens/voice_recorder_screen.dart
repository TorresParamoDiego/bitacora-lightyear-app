import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_recorder_service.dart';
import '../services/voice_api_service.dart';
import '../widgets/slide_controls.dart';
import '../models/voice_note.dart';
import '../services/transcription_api_service.dart';
import '../widgets/transcription_panel.dart';

/// Pantalla principal que gestiona el módulo de notas de voz de Bitácora Lightyear.
/// 
/// Implementa una máquina de estados finita ([RecorderState]) para controlar 
/// el flujo del usuario: inactivo, grabando, procesando, éxito y error.
/// Coordina el temporizador estricto de 3 minutos, la invocación de servicios
/// de audio/API y muestra los cuadros de diálogo de seguridad para cancelar.
enum RecorderState { idle, recording, processing, success, error }

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  final AudioRecorderService _audioService = AudioRecorderService();
  final VoiceApiService _apiService = VoiceApiService();

  RecorderState _state = RecorderState.idle;
  Timer? _timer;
  int _secondsElapsed = 0;
  final int _maxSeconds = 180;

  String? _recordedFilePath;
  String _errorMessage = '';
  VoiceNoteResponse? _serverResponse;

  @override
  void dispose() {
    _timer?.cancel();
    _audioService.dispose();
    super.dispose();
  }

  void _startRecording() async {
    try {
      await _audioService.startRecording();
      setState(() {
        _state = RecorderState.recording;
        _secondsElapsed = 0;
        _errorMessage = '';
        _serverResponse = null;
      });
      _startTimer();
    } catch (e) {
      _showSnackBar('Error: Verifica los permisos del micrófono');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
      if (_secondsElapsed >= _maxSeconds) {
        _stopRecordingAndSave(autoStopped: true);
      }
    });
  }

  void _stopRecordingAndSave({bool autoStopped = false}) async {
    _timer?.cancel();
    final path = await _audioService.stopRecording();
    
    if (_secondsElapsed < 2) {
      _cancelRecording();
      _showSnackBar('La grabación es demasiado corta.');
      return;
    }
    if (autoStopped) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false, // Obliga a interactuar con el botón
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            icon: const Icon(Icons.timer_off_outlined, size: 48, color: Colors.orange),
            title: const Text('Límite alcanzado', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text(
              'Se alcanzó el tiempo máximo de grabación (3:00 min).\nLa captura se detuvo automáticamente para optimizar el análisis.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black87),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C4EE5),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido, procesar audio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    }
    // --------------------------------------------------

    setState(() {
      _state = RecorderState.processing;
      _recordedFilePath = path;
    });
    
    _uploadAudio();
  }

  Future<void> _uploadAudio() async {
    if (_recordedFilePath == null) return;
    try {
      final response = await _apiService.uploadVoiceNote(_recordedFilePath!);
      setState(() {
        _state = RecorderState.success;
        _serverResponse = response;
      });
    } catch (e) {
      setState(() {
        _state = RecorderState.error;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _cancelRecording() async {
    _timer?.cancel();
    await _audioService.cancelRecording();
    _resetState();
  }

  void _resetState() {
    setState(() {
      _state = RecorderState.idle;
      _secondsElapsed = 0;
      _recordedFilePath = null;
      _serverResponse = null;
      _errorMessage = '';
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _requestCancel() async {
    // 1. Pausamos el tiempo y el audio real del micrófono
    _timer?.cancel();
    await _audioService.pauseRecording();

    // 2. Mostramos el cuadro de confirmación
    if (!mounted) return;
    final bool? shouldCancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Obliga al usuario a tocar un botón
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: const Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Colors.redAccent,
          ),
          title: const Text(
            '¿Cancelar grabación?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Si cancelas ahora, el audio no se guardará y no se creará ningún registro en tu bitácora.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87, fontSize: 16),
              ),
              const SizedBox(height: 24),
              // Botones
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.mic, color: Colors.white),
                label: const Text(
                  'Continuar grabando',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C4EE5),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(
                  Icons.cancel_presentation,
                  color: Colors.white,
                ),
                label: const Text(
                  'Cancelar grabación',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Caja de información de seguridad
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF5C4EE5),
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirmación de seguridad',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'La interrupción forzada requiere verificación para evitar pérdidas accidentales durante operaciones de campo.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    // 3. Procesamos la decisión
    if (shouldCancel == true) {
      _cancelRecording(); // Se destruye el audio
    } else {
      await _audioService.resumeRecording(); // Se reanuda el audio
      _startTimer(); // Se reanuda el cronómetro
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryPurple = Color(0xFF5C4EE5);
    const primaryGreen = Color(0xFF2ECC71);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () {},
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grabar Nota De Voz',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Bitácora Lightyear',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundColor: primaryPurple,
              radius: 18,
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_state == RecorderState.idle) _buildIdleView(primaryPurple),
              if (_state == RecorderState.recording)
                _buildRecordingView(primaryPurple),
              if (_state == RecorderState.processing)
                _buildProcessingView(primaryGreen),
              if (_state == RecorderState.success && _serverResponse != null)
                _buildSuccessView(primaryPurple, primaryGreen),
              if (_state == RecorderState.error) _buildErrorView(),
            ],
          ),
        ),
      ),
    );
  }

  // --- VISTAS POR ESTADO ---

  Widget _buildIdleView(Color primaryColor) {
    return Expanded(
      child: Column(
        children: [
          // Tarjeta de instrucciones
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Nueva nota de voz',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.auto_awesome, color: Color(0xFF5C4EE5)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Habla con claridad describiendo tus tareas, eventos o compromisos. El sistema detectará fechas y prioridades automáticamente.',
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEECFC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: Color(0xFF5C4EE5),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Duración máxima: 3:00 min',
                        style: TextStyle(
                          color: Color(0xFF5C4EE5),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Botón central con aros concéntricos
          GestureDetector(
            onTap: _startRecording,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.05),
              ),
              child: Center(
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withOpacity(0.15),
                  ),
                  child: Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor,
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic, color: Colors.white, size: 40),
                          SizedBox(height: 4),
                          Text(
                            'TOCA PARA INICIAR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'Micrófono listo • Reducción de ruido activa',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRecordingView(Color primaryColor) {
    return Expanded(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 10, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'GRABANDO...',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text(
            _formatTime(_secondsElapsed),
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const Text(
            '/ 03:00',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 80),

          // Placeholder visual de las ondas de audio
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(15, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6,
                height: (index % 2 == 0) ? 20.0 : 40.0,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),

          const Spacer(),
          const Text(
            '<- Desliza para Cancelar  |  Desliza para Guardar ->',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SlideControls(
            onCancel: _requestCancel,
            onStopAndSave: () => _stopRecordingAndSave(autoStopped: false),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProcessingView(Color primaryGreen) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primaryGreen),
          const SizedBox(height: 24),
          const Text(
            'Subiendo audio al servidor...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'No cierres la aplicación',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(Color primaryPurple, Color primaryGreen) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Grabación finalizada',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: primaryGreen, size: 28),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'El audio se ha conservado y procesado correctamente en el servidor.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryPurple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic, color: primaryPurple),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _serverResponse!.archivoAudio,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_serverResponse!.tamanoBytes / 1024).toStringAsFixed(1)} KB • ${_serverResponse!.formato.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {
              final path = _recordedFilePath;
              if (path == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Transcripción')),
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TranscriptionPanel(
                      audioPath: path,
                      apiService: TranscriptionApiService(),
                    ),
                  ),
                ),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPurple,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Continuar con transcripción',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _resetState,
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: Colors.red.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Descartar y volver a grabar',
              style: TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 24),
          const Text(
            'Error al procesar el audio',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _uploadAudio,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Reintentar conexión',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _resetState,
            child: const Text(
              'Volver al inicio',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
