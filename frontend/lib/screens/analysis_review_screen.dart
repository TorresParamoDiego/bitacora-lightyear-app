import 'package:flutter/material.dart';
import '../models/extracted_item.dart';
import '../services/analysis_api_service.dart';
import 'home_screen.dart';
/// Pantalla de revisión de resultados tras el análisis automático de transcripciones.
/// Presenta los elementos en bloques visuales diferenciados (Tareas, Recordatorios, Eventos),
/// permite editarlos, eliminarlos, modificarlos y guardarlos en el backend.
class AnalysisReviewScreen extends StatefulWidget {
  const AnalysisReviewScreen({
    super.key,
    required this.initialItems,
    this.rawTranscription,
    this.audioPath,
    this.apiService,
  });

  final List<ExtractedItem> initialItems;
  final String? rawTranscription;
  final String? audioPath;
  final AnalysisApiService? apiService;

  @override
  State<AnalysisReviewScreen> createState() => _AnalysisReviewScreenState();
}

class _AnalysisReviewScreenState extends State<AnalysisReviewScreen> {
  late List<ExtractedItem> _items;
  late final AnalysisApiService _apiService;
  bool _isSaving = false;
  bool _simulateStorageError = false;
  String? _storageErrorMessage;
  String _selectedFilter = 'all'; // 'all', 'task', 'reminder', 'event'

  static const Color primaryPurple = Color(0xFF5C4EE5);
  static const Color secondaryGreen = Color(0xFF2ECC71);
  static const Color tertiaryBlue = Color(0xFF3498DB);
  static const Color reminderAmber = Color(0xFFE67E22);

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    _apiService = widget.apiService ?? AnalysisApiService();
  }

  /// Permite al usuario cancelar el guardado y regresar a la vista principal sin crear ningún registro.
  Future<void> _confirmDiscardAndExit() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 420),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

        title: const Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '¿Cancelar guardado?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),

        content: const SingleChildScrollView(
          child: Text(
            'Se cancelará la operación y no se creará ningún registro '
            'en la base de datos. Volverás a la pantalla principal.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),

        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Continuar editando'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Descartar y salir',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  /// Diálogo previo de confirmación antes de guardar en la base de datos.
  Future<void> _promptSaveConfirmation() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay elementos para guardar.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: primaryPurple),
            SizedBox(width: 8),
            Text(
              'Confirmar guardado',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          '¿Deseas confirmar el guardado de ${_items.length} elemento(s) revisado(s) en la base de datos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Confirmar y Guardar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _executeSave();
    }
  }

  /// Ejecuta el guardado efectivo en Supabase a través del backend, con manejo y recuperación de errores.
  Future<void> _executeSave() async {
    setState(() {
      _isSaving = true;
      _storageErrorMessage = null;
    });

    try {
      final savedCount = await _apiService.saveConfirmedItems(
        _items,
        audioPath: widget.audioPath,
        simulateError: _simulateStorageError,
      );

      if (!mounted) return;

      // Notificación de éxito
      
      // Confirmación de éxito después de guardar
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            Icons.check_circle_outline,
            color: secondaryGreen,
            size: 54,
          ),
          title: const Text(
            'Elementos guardados',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Se han guardado $savedCount elementos correctamente '
            'en tu bitácora.',
            textAlign: TextAlign.center,
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                    builder: (_) => const HomeScreen(),
                  ),
                  (route) => false,
                );
              },
              child: const Text(
                'Aceptar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

    } catch (e) {
      if (!mounted) return;

      final errorMsg = e.toString().replaceFirst('AnalysisApiException: ', '');
      setState(() {
        _storageErrorMessage = errorMsg;
      });

      // Diálogo de error claro que verifica que los datos permanecen disponibles
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
          title: const Text(
            'Error de almacenamiento',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMsg, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Los datos y cambios permanecen disponibles en pantalla para realizar otro intento.',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar y Revisar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _executeSave();
              },
              child: const Text(
                'Reintentar Guardado',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  List<ExtractedItem> get _filteredItems {
    if (_selectedFilter == 'all') return _items;
    return _items.where((i) => i.type == _selectedFilter).toList();
  }

  int get _taskCount => _items.where((i) => i.type == 'task').length;
  int get _reminderCount => _items.where((i) => i.type == 'reminder').length;
  int get _eventCount => _items.where((i) => i.type == 'event').length;

  void _deleteItem(int indexInFiltered) {
    final itemToRemove = _filteredItems[indexInFiltered];
    final originalIndex = _items.indexOf(itemToRemove);
    setState(() {
      _items.removeAt(originalIndex);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Se eliminó "${itemToRemove.title}".'),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: Colors.amberAccent,
          onPressed: () {
            setState(() {
              _items.insert(originalIndex, itemToRemove);
            });
          },
        ),
      ),
    );
  }

  Future<void> _showEditDialog(ExtractedItem item, int originalIndex) async {
    final titleController = TextEditingController(text: item.title);
    final descController = TextEditingController(text: item.description);
    String selectedType = item.type;
    String? selectedPriority = item.priority;
    String? selectedDate = item.date;
    String? selectedTime = item.time;
    String selectedStatus = item.status;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              constraints: const BoxConstraints(maxWidth: 480),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    item.isTask
                        ? Icons.task_alt
                        : (item.isReminder ? Icons.alarm : Icons.event),
                    color: primaryPurple,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Editar elemento',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tipo
                      const Text(
                        'Tipo de elemento',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),

                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'task',
                            child: Text(
                              'Tarea (actividad a realizar)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'reminder',
                            child: Text(
                              'Recordatorio (información a tener presente)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'event',
                            child: Text(
                              'Evento (cita, reunión o actividad)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedType = val;
                              if (selectedType != 'task') {
                                selectedPriority = null;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // Título
                      const Text(
                        'Título',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: 'Título breve',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Descripción
                      const Text(
                        'Descripción',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Detalles relevantes de la transcripción',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Prioridad (solo para tareas)
                      if (selectedType == 'task') ...[
                        const Text(
                          'Prioridad',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String?>(
                          initialValue: selectedPriority,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: null,
                              child: Text('Sin prioridad definida'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('Alta (urgente)'),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text('Media'),
                            ),
                            DropdownMenuItem(
                              value: 'low',
                              child: Text('Baja (no urge)'),
                            ),
                          ],
                          onChanged: (val) =>
                              setDialogState(() => selectedPriority = val),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Fecha
                      const Text(
                        'Fecha',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                selectedDate ?? 'Sin fecha asignada',
                                style: TextStyle(
                                  color: selectedDate != null
                                      ? Colors.black87
                                      : Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                final now = DateTime.now();
                                DateTime initial = now;
                                if (selectedDate != null) {
                                  final parsed = DateTime.tryParse(
                                    selectedDate!,
                                  );
                                  if (parsed != null) initial = parsed;
                                }
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: initial,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  final m = picked.month.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  final d = picked.day.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  setDialogState(() {
                                    selectedDate = '${picked.year}-$m-$d';
                                  });
                                }
                              },
                            ),
                          ),
                          if (selectedDate != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear, color: Colors.red),
                              tooltip: 'Borrar fecha',
                              onPressed: () =>
                                  setDialogState(() => selectedDate = null),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Hora
                      const Text(
                        'Hora',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.access_time, size: 18),
                              label: Text(
                                selectedTime ?? 'Sin hora asignada',
                                style: TextStyle(
                                  color: selectedTime != null
                                      ? Colors.black87
                                      : Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                TimeOfDay initialTime = TimeOfDay.now();
                                if (selectedTime != null) {
                                  final parts = selectedTime!.split(':');
                                  if (parts.length == 2) {
                                    final h = int.tryParse(parts[0]) ?? 12;
                                    final m = int.tryParse(parts[1]) ?? 0;
                                    initialTime = TimeOfDay(hour: h, minute: m);
                                  }
                                }
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: initialTime,
                                );
                                if (picked != null) {
                                  final h = picked.hour.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  final m = picked.minute.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  setDialogState(() {
                                    selectedTime = '$h:$m';
                                  });
                                }
                              },
                            ),
                          ),
                          if (selectedTime != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear, color: Colors.red),
                              tooltip: 'Borrar hora',
                              onPressed: () =>
                                  setDialogState(() => selectedTime = null),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Estado
                      const Text(
                        'Estado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pendiente'),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('Completado / Realizado'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelado'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedStatus = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final newTitle = titleController.text.trim();
                    if (newTitle.isEmpty) return;
                    setState(() {
                      _items[originalIndex] = ExtractedItem(
                        type: selectedType,
                        title: newTitle,
                        description: descController.text.trim(),
                        priority: selectedPriority,
                        date: selectedDate,
                        time: selectedTime,
                        status: selectedStatus,
                      );
                    });
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text(
                    'Guardar cambios',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addNewItem() {
    final newItem = ExtractedItem(
      type: 'task',
      title: 'Nueva tarea',
      description: '',
      status: 'pending',
    );
    setState(() {
      _items.add(newItem);
    });
    _showEditDialog(newItem, _items.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscardAndExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Cancelar y volver',
            onPressed: _confirmDiscardAndExit,
          ),
          title: const Text(
            'Revisión de Elementos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: Colors.white,
          elevation: 0.5,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: primaryPurple),
              tooltip: 'Agregar elemento manualmente',
              onPressed: _addNewItem,
            ),
            PopupMenuButton<String>(
              tooltip: 'Opciones de validación',
              icon: Icon(
                _simulateStorageError ? Icons.bug_report : Icons.more_vert,
                color: _simulateStorageError
                    ? Colors.deepOrange
                    : Colors.black87,
              ),
              onSelected: (val) {
                if (val == 'toggle_error') {
                  setState(() {
                    _simulateStorageError = !_simulateStorageError;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      backgroundColor: _simulateStorageError
                          ? Colors.deepOrange
                          : Colors.grey.shade800,
                      content: Text(
                        _simulateStorageError
                            ? 'Simulación de error de guardado ACTIVADA'
                            : 'Simulación de error de guardado DESACTIVADA',
                      ),
                    ),
                  );
                } else if (val == 'discard') {
                  _confirmDiscardAndExit();
                }
              },
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem(
                  value: 'toggle_error',
                  checked: _simulateStorageError,
                  child: const Text('Simular error de almacenamiento (QA)'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'discard',
                  child: Text(
                    'Cancelar y descartar todo',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_simulateStorageError)
                Container(
                  color: Colors.deepOrange.shade50,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bug_report,
                        size: 18,
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Modo QA activo: El guardado provocará un error de almacenamiento para validar la recuperación.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () =>
                            setState(() => _simulateStorageError = false),
                        child: const Text(
                          'Desactivar',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.deepOrange,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_storageErrorMessage != null)
                Container(
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _storageErrorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () =>
                            setState(() => _storageErrorMessage = null),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              // Resumen de elementos y filtro por tipo
              _buildSummaryAndFilters(),

              // Lista de tarjetas en bloques visuales diferenciados
              Expanded(
                child: _filteredItems.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          final originalIndex = _items.indexOf(item);
                          return _buildItemCard(item, index, originalIndex);
                        },
                      ),
              ),

              // Barra inferior con botón de confirmación y guardado
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: primaryPurple, size: 20),
              const SizedBox(width: 8),
              Text(
                '${_items.length} elementos identificados',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '$_taskCount T • $_reminderCount R • $_eventCount E',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Todos (${_items.length})',
                  'all',
                  Colors.black87,
                ),
                const SizedBox(width: 8),
                _buildFilterChip('Tareas ($_taskCount)', 'task', primaryPurple),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Recordatorios ($_reminderCount)',
                  'reminder',
                  reminderAmber,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Eventos ($_eventCount)',
                  'event',
                  tertiaryBlue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String type, Color activeColor) {
    final isSelected = _selectedFilter == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? activeColor : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(color: isSelected ? activeColor : Colors.grey.shade300),
      onSelected: (_) => setState(() => _selectedFilter = type),
    );
  }

  Widget _buildItemCard(
    ExtractedItem item,
    int filteredIndex,
    int originalIndex,
  ) {
    Color typeColor;
    IconData typeIcon;
    if (item.isTask) {
      typeColor = primaryPurple;
      typeIcon = Icons.check_circle_outline;
    } else if (item.isReminder) {
      typeColor = reminderAmber;
      typeIcon = Icons.notifications_none;
    } else {
      typeColor = tertiaryBlue;
      typeIcon = Icons.event_outlined;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: typeColor.withValues(alpha: 0.25), width: 1.2),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado de la tarjeta: Etiqueta de tipo y botones de acción
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 14, color: typeColor),
                      const SizedBox(width: 5),
                      Text(
                        item.typeLabel.toUpperCase(),
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: Colors.black54,
                  ),
                  tooltip: 'Editar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showEditDialog(item, originalIndex),
                ),
                const SizedBox(width: 14),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Eliminar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _deleteItem(filteredIndex),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Título
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            // Descripción (si difiere del título y existe)
            if (item.description.isNotEmpty &&
                item.description != item.title) ...[
              const SizedBox(height: 6),
              Text(
                item.description,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Bloque de datos disponibles (NUNCA mostrar campos nulos)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Prioridad (solo para tareas cuando esté definida)
                if (item.isTask &&
                    item.priority != null &&
                    item.priority!.isNotEmpty)
                  _buildDataBadge(
                    icon: Icons.flag_outlined,
                    label: 'Prioridad ${item.priorityLabel ?? item.priority}',
                    color: item.priority == 'high'
                        ? Colors.red.shade700
                        : (item.priority == 'medium'
                              ? Colors.orange.shade800
                              : Colors.teal),
                  ),

                // Fecha (cuando exista)
                if (item.date != null && item.date!.isNotEmpty)
                  _buildDataBadge(
                    icon: Icons.calendar_today_outlined,
                    label: item.formattedDate ?? item.date!,
                    color: Colors.indigo.shade700,
                  ),

                // Hora (cuando exista)
                if (item.time != null && item.time!.isNotEmpty)
                  _buildDataBadge(
                    icon: Icons.access_time,
                    label: item.time!,
                    color: Colors.blueGrey.shade800,
                  ),

                // Estado (para tareas y eventos)
                _buildDataBadge(
                  icon: item.status == 'completed'
                      ? Icons.check_circle_outline
                      : (item.status == 'cancelled'
                            ? Icons.cancel_outlined
                            : Icons.pending_outlined),
                  label: item.statusLabel,
                  color: item.status == 'completed'
                      ? secondaryGreen
                      : (item.status == 'cancelled'
                            ? Colors.red
                            : Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No hay elementos en esta categoría',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Puedes agregar un nuevo elemento manualmente tocando el botón "+".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar elemento'),
              onPressed: _addNewItem,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Botón Cancelar (descarta y comprueba que no se cree ningún registro)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              onPressed: _isSaving ? null : _confirmDiscardAndExit,
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Botón Confirmar y Guardar (pide confirmación, persiste, notifica y redirige)
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              onPressed: _isSaving ? null : _promptSaveConfirmation,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.cloud_upload_outlined,
                      color: Colors.white,
                    ),
              label: Text(
                _isSaving
                    ? 'Guardando...'
                    : 'Confirmar y Guardar (${_items.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
