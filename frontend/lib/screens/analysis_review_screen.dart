import 'package:flutter/material.dart';
import '../models/activity_item.dart';
import '../models/extracted_item.dart';
import '../models/notification_preferences.dart';
import '../services/analysis_api_service.dart';
import '../services/notification_schedule_service.dart';
import '../services/reminder_notification_service.dart';
import 'home_screen.dart';
import '../widgets/activity_edit_dialog.dart';

/// Pantalla de revisión de resultados tras el análisis automático de transcripciones.
/// Presenta los elementos en bloques visuales diferenciados (Tareas, Recordatorios, Eventos),
/// permite editarlos, eliminarlos, personalizar sus avisos y guardarlos.
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
  final Map<int, List<int>> _customOffsetsByIndex = {};
  TypeNotificationDefaults _typeDefaults = TypeNotificationDefaults();

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
    _loadTypeDefaults();
  }

  Future<void> _loadTypeDefaults() async {
    final loaded = await NotificationScheduleService.instance.loadTypeDefaults();
    if (!mounted) return;
    setState(() {
      _typeDefaults = loaded;
    });
  }

  // Reasigna las claves de `_customOffsetsByIndex` al insertar o eliminar elementos.
  void _remapOffsetsAfterDelete(int removedIndex) {
    final updated = <int, List<int>>{};
    _customOffsetsByIndex.forEach((idx, offsets) {
      if (idx < removedIndex) {
        updated[idx] = offsets;
      } else if (idx > removedIndex) {
        updated[idx - 1] = offsets;
      }
    });
    _customOffsetsByIndex
      ..clear()
      ..addAll(updated);
  }

  void _remapOffsetsAfterInsert(int insertedIndex) {
    final updated = <int, List<int>>{};
    _customOffsetsByIndex.forEach((idx, offsets) {
      if (idx >= insertedIndex) {
        updated[idx + 1] = offsets;
      } else {
        updated[idx] = offsets;
      }
    });
    _customOffsetsByIndex
      ..clear()
      ..addAll(updated);
  }

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

  bool get _hasRecurringSeries => _items.any(
        (item) =>
            RegExp(r'\(\d+/\d+\)$').hasMatch(item.title.trim()) ||
            item.title.toLowerCase().startsWith('generar más recordatorios:') ||
            item.description.toLowerCase().contains('ocurrencia '),
      );

  bool get _hasInferredOrBroadDate => _items.any(
        (item) =>
            item.description.toLowerCase().contains('fecha inferida') ||
            item.description.toLowerCase().contains('fecha aproximada'),
      );

  Future<void> _promptSaveConfirmation() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay elementos para guardar.')),
      );
      return;
    }

    final hasRecurring = _hasRecurringSeries;
    final hasInferredDate = _hasInferredOrBroadDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: primaryPurple),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirmar guardado',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Deseas confirmar el guardado de ${_items.length} elemento(s) revisado(s) en la base de datos?',
            ),
            if (hasRecurring || hasInferredDate) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasRecurring)
                      const Text(
                        '• Se detectaron recordatorios/ocurrencias recurrentes (incluyendo seguimiento si aplica).',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    if (hasInferredDate) ...[
                      if (hasRecurring) const SizedBox(height: 4),
                      const Text(
                        '• Algunos elementos tienen fecha inferida o aproximada; revísala antes de confirmar.',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
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

  // Vincula cada ítem guardado en la BD con sus `offset_minutes` personalizados o default.
  Future<void> _syncSavedSchedules() async {
    final savedItems = await _apiService.getSavedItems();
    if (savedItems.isEmpty) return;

    final byIndex = <int, List<int>>{};
    for (var i = 0; i < _items.length && i < savedItems.length; i++) {
      final custom = _customOffsetsByIndex[i];
      if (custom != null) {
        byIndex[i] = custom;
      }
    }

    final customById = <String, List<int>>{};
    for (var i = 0; i < savedItems.length; i++) {
      final act = ActivityItem(
        id: savedItems[i].title,
        type: savedItems[i].type,
        title: savedItems[i].title,
        description: savedItems[i].description,
        priority: savedItems[i].priority,
        itemDate: savedItems[i].date,
        itemTime: savedItems[i].time,
        status: savedItems[i].status,
      );
      // Busca coincidencia por índice si el orden coincide con lo guardado.
      final matchByIdx = byIndex[i];
      if (matchByIdx != null) {
        customById[act.id] = matchByIdx;
      }
    }

    ReminderNotificationService.instance.syncReminders(
      savedItems
          .map(
            (e) => ActivityItem(
              id: e.title,
              type: e.type,
              title: e.title,
              description: e.description,
              priority: e.priority,
              itemDate: e.date,
              itemTime: e.time,
              status: e.status,
            ),
          )
          .toList(),
      replaceAll: false,
      defaults: _typeDefaults,
      customOffsetsByItemId: customById,
    );

    // Sincroniza en Supabase los schedules de los ítems creados más recientes si tienen fecha.
    for (var i = 0; i < _items.length; i++) {
      final custom = _customOffsetsByIndex[i];
      if (custom == null) continue;
      final candidate = savedItems.firstWhere(
        (s) =>
            s.title == _items[i].title &&
            s.type == _items[i].type &&
            s.date == _items[i].date,
        orElse: () => _items[i],
      );
      if (candidate.date != null && candidate.date!.isNotEmpty) {
        // Solo sincroniza en BD si el backend devolvió un id real; de lo contrario se sincronizará al cargar actividades.
        final asActivity = ActivityItem(
          id: '',
          type: candidate.type,
          title: candidate.title,
          description: candidate.description,
          priority: candidate.priority,
          itemDate: candidate.date,
          itemTime: candidate.time,
          status: candidate.status,
        );
        await NotificationScheduleService.instance.syncItemSchedules(
          item: asActivity,
          defaults: _typeDefaults,
          customOffsets: custom,
        );
      }
    }
  }

  Future<void> _executeSave() async {
    setState(() {
      _isSaving = true;
      _storageErrorMessage = null;
    });

    try {
      final savedCount = await _apiService.saveConfirmedItems(
        _items,
        audioPath: widget.audioPath,
        transcript: widget.rawTranscription,
        simulateError: _simulateStorageError,
      );

      await _syncSavedSchedules();

      if (!mounted) return;

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
                  MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
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
    final previousCustom = _customOffsetsByIndex[originalIndex];

    setState(() {
      _items.removeAt(originalIndex);
      _remapOffsetsAfterDelete(originalIndex);
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
              _remapOffsetsAfterInsert(originalIndex);
              if (previousCustom != null) {
                _customOffsetsByIndex[originalIndex] = previousCustom;
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _showEditDialog(ExtractedItem item, int originalIndex) async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityEditDialog(
        primaryColor: primaryPurple,
        typeDefaults: _typeDefaults,
        item: ActivityDialogData(
          title: item.title,
          description: item.description,
          type: item.type,
          priority: item.priority,
          date: item.date,
          time: item.time,
          status: item.status,
          notificationOffsets: _customOffsetsByIndex[originalIndex],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _items[originalIndex] = ExtractedItem(
          type: result['type'],
          title: result['title'],
          description: result['description'] ?? '',
          priority: result['priority'],
          date: result['date'],
          time: result['time'],
          status: result['status'],
        );
        if (result['notification_offsets'] is List) {
          _customOffsetsByIndex[originalIndex] =
              List<int>.from(result['notification_offsets'] as List);
        }
      });
    }
  }

  Future<void> _addNewItem() async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityEditDialog(
        primaryColor: primaryPurple,
        typeDefaults: _typeDefaults,
        item: ActivityDialogData.empty(defaultType: 'task'),
      ),
    );

    if (result != null) {
      final newIndex = _items.length;
      setState(() {
        _items.add(
          ExtractedItem(
            type: result['type'],
            title: result['title'],
            description: result['description'] ?? '',
            priority: result['priority'],
            date: result['date'],
            time: result['time'],
            status: result['status'],
          ),
        );
        if (result['notification_offsets'] is List) {
          _customOffsetsByIndex[newIndex] =
              List<int>.from(result['notification_offsets'] as List);
        }
      });
    }
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
              _buildSummaryAndFilters(),
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
                          return _buildItemCard(
                            item,
                            index,
                            originalIndex,
                          );
                        },
                      ),
              ),
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

    final effectiveOffsets = _typeDefaults.resolveOffsetsForItem(
      itemType: item.type,
      customItemOffsets: _customOffsetsByIndex[originalIndex],
    );

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
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
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
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
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
                if (item.date != null && item.date!.isNotEmpty)
                  _buildDataBadge(
                    icon: Icons.calendar_today_outlined,
                    label: item.formattedDate ?? item.date!,
                    color: Colors.indigo.shade700,
                  ),
                if (item.time != null && item.time!.isNotEmpty)
                  _buildDataBadge(
                    icon: Icons.access_time,
                    label: item.time!,
                    color: Colors.blueGrey.shade800,
                  ),
                _buildDataBadge(
                  icon: Icons.notifications_active_outlined,
                  label: effectiveOffsets.isEmpty
                      ? 'Sin avisos'
                      : 'Avisos: ${effectiveOffsets.map((m) => NotificationOffset(m).formatLabel()).join(', ')}',
                  color: typeColor,
                ),
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