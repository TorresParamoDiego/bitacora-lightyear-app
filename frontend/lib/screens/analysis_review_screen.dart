import 'package:flutter/material.dart';
import '../models/extracted_item.dart';
import '../services/analysis_api_service.dart';

/// Pantalla de revisión de resultados tras el análisis automático de transcripciones.
/// Presenta los elementos en bloques visuales diferenciados (Tareas, Recordatorios, Eventos),
/// permite editarlos, eliminarlos, modificarlos y guardarlos en el backend.
class AnalysisReviewScreen extends StatefulWidget {
  const AnalysisReviewScreen({
    super.key,
    required this.initialItems,
    this.rawTranscription,
    this.apiService,
  });

  final List<ExtractedItem> initialItems;
  final String? rawTranscription;
  final AnalysisApiService? apiService;

  @override
  State<AnalysisReviewScreen> createState() => _AnalysisReviewScreenState();
}

class _AnalysisReviewScreenState extends State<AnalysisReviewScreen> {
  late List<ExtractedItem> _items;
  late final AnalysisApiService _apiService;
  bool _isSaving = false;
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
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  const Text('Editar elemento', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
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
                      const Text('Tipo de elemento', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'task', child: Text('Tarea (actividad a realizar)')),
                          DropdownMenuItem(value: 'reminder', child: Text('Recordatorio (información a tener presente)')),
                          DropdownMenuItem(value: 'event', child: Text('Evento (cita, reunión o actividad)')),
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
                      const Text('Título', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: 'Título breve',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Descripción
                      const Text('Descripción', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Detalles relevantes de la transcripción',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Prioridad (solo para tareas)
                      if (selectedType == 'task') ...[
                        const Text('Prioridad', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String?>(
                          initialValue: selectedPriority,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Sin prioridad definida')),
                            DropdownMenuItem(value: 'high', child: Text('Alta (urgente)')),
                            DropdownMenuItem(value: 'medium', child: Text('Media')),
                            DropdownMenuItem(value: 'low', child: Text('Baja (no urge)')),
                          ],
                          onChanged: (val) => setDialogState(() => selectedPriority = val),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Fecha
                      const Text('Fecha', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              ),
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                selectedDate ?? 'Sin fecha asignada',
                                style: TextStyle(
                                  color: selectedDate != null ? Colors.black87 : Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                final now = DateTime.now();
                                DateTime initial = now;
                                if (selectedDate != null) {
                                  final parsed = DateTime.tryParse(selectedDate!);
                                  if (parsed != null) initial = parsed;
                                }
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: initial,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  final m = picked.month.toString().padLeft(2, '0');
                                  final d = picked.day.toString().padLeft(2, '0');
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
                              onPressed: () => setDialogState(() => selectedDate = null),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Hora
                      const Text('Hora', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              ),
                              icon: const Icon(Icons.access_time, size: 18),
                              label: Text(
                                selectedTime ?? 'Sin hora asignada',
                                style: TextStyle(
                                  color: selectedTime != null ? Colors.black87 : Colors.grey,
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
                                  final h = picked.hour.toString().padLeft(2, '0');
                                  final m = picked.minute.toString().padLeft(2, '0');
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
                              onPressed: () => setDialogState(() => selectedTime = null),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Estado
                      const Text('Estado', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                          DropdownMenuItem(value: 'completed', child: Text('Completado / Realizado')),
                          DropdownMenuItem(value: 'cancelled', child: Text('Cancelado')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedStatus = val);
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  child: const Text('Guardar cambios', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Future<void> _saveAllConfirmed() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay elementos para guardar.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final savedCount = await _apiService.saveConfirmedItems(_items);
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.check_circle_outline, color: secondaryGreen, size: 54),
          title: const Text('Elementos guardados', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            'Se han guardado $savedCount elementos correctamente en tu bitácora.',
            textAlign: TextAlign.center,
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop(); // Cierra diálogo
                Navigator.of(context).pop(); // Vuelve a la pantalla principal
              },
              child: const Text('Aceptar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
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
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Resumen de elementos y filtro por tipo
            _buildSummaryAndFilters(),

            // Lista de tarjetas en bloques visuales diferenciados
            Expanded(
              child: _filteredItems.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              Text(
                '$_taskCount T • $_reminderCount R • $_eventCount E',
                style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Todos (${_items.length})', 'all', Colors.black87),
                const SizedBox(width: 8),
                _buildFilterChip('Tareas ($_taskCount)', 'task', primaryPurple),
                const SizedBox(width: 8),
                _buildFilterChip('Recordatorios ($_reminderCount)', 'reminder', reminderAmber),
                const SizedBox(width: 8),
                _buildFilterChip('Eventos ($_eventCount)', 'event', tertiaryBlue),
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
      side: BorderSide(
        color: isSelected ? activeColor : Colors.grey.shade300,
      ),
      onSelected: (_) => setState(() => _selectedFilter = type),
    );
  }

  Widget _buildItemCard(ExtractedItem item, int filteredIndex, int originalIndex) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.black54),
                  tooltip: 'Editar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showEditDialog(item, originalIndex),
                ),
                const SizedBox(width: 14),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
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
            if (item.description.isNotEmpty && item.description != item.title) ...[
              const SizedBox(height: 6),
              Text(
                item.description,
                style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.3),
              ),
            ],

            const SizedBox(height: 12),

            // Bloque de datos disponibles (NUNCA mostrar campos nulos)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Prioridad (solo para tareas cuando esté definida)
                if (item.isTask && item.priority != null && item.priority!.isNotEmpty)
                  _buildDataBadge(
                    icon: Icons.flag_outlined,
                    label: 'Prioridad ${item.priorityLabel ?? item.priority}',
                    color: item.priority == 'high'
                        ? Colors.red.shade700
                        : (item.priority == 'medium' ? Colors.orange.shade800 : Colors.teal),
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
                      : (item.status == 'cancelled' ? Icons.cancel_outlined : Icons.pending_outlined),
                  label: item.statusLabel,
                  color: item.status == 'completed'
                      ? secondaryGreen
                      : (item.status == 'cancelled' ? Colors.red : Colors.grey.shade700),
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
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
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
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        onPressed: _isSaving ? null : _saveAllConfirmed,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload_outlined, color: Colors.white),
        label: Text(
          _isSaving
              ? 'Guardando elementos...'
              : 'Guardar elementos confirmados (${_items.length})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
