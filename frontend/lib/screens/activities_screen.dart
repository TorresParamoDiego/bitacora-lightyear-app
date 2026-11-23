import 'package:flutter/material.dart';
import '../models/activity_item.dart';
import '../models/notification_preferences.dart';
import '../models/recording_item.dart';
import '../services/activities_api_service.dart';
import '../services/notification_schedule_service.dart';
import '../widgets/activity_edit_dialog.dart';

class ActivitiesScreen extends StatefulWidget {
  final String? initialItemId;
  final VoidCallback? onInitialItemHandled;

  const ActivitiesScreen({
    super.key,
    this.initialItemId,
    this.onInitialItemHandled,
  });

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  final _api = ActivitiesApiService();

  bool _loading = true;
  String? _error;

  List<ActivityItem> _allActivities = [];
  List<RecordingItem> _recordings = [];
  TypeNotificationDefaults _typeDefaults = TypeNotificationDefaults();
  Map<String, List<int>> _customOffsetsByItemId = {};

  String? _selectedRecordingId;
  String _selectedType = 'all';
  String _selectedStatus = 'all';
  String _sortBy = 'date_asc';

  String? _lastHandledInitialItemId;

  static const Color primaryPurple = Color(0xFF5C4EE5);
  static const Color secondaryGreen = Color(0xFF2ECC71);
  static const Color tertiaryBlue = Color(0xFF3498DB);
  static const Color reminderAmber = Color(0xFFE67E22);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ActivitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialItemId != null &&
        widget.initialItemId != oldWidget.initialItemId) {
      _lastHandledInitialItemId = null;
      _openInitialItemIfNeeded();
    }
  }

  String _recordingLabel(RecordingItem rec) {
    final text = rec.transcript?.trim();
    if (text != null && text.isNotEmpty) {
      return text.length > 42 ? '${text.substring(0, 42)}…' : text;
    }
    return 'Grabación ${rec.id.substring(0, rec.id.length > 8 ? 8 : rec.id.length)}';
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'task':
        return 'Tarea';
      case 'reminder':
        return 'Recordatorio';
      case 'event':
        return 'Evento';
      default:
        return type;
    }
  }

  String? _priorityLabel(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Media';
      case 'low':
        return 'Baja';
      default:
        return priority;
    }
  }

  String _statusLabel(String? status) {
    switch ((status ?? 'pending').toLowerCase()) {
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      case 'pending':
      default:
        return 'Pendiente';
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getActivities(recordingId: _selectedRecordingId),
        _api.getRecordings(),
        NotificationScheduleService.instance.loadTypeDefaults(),
      ]);
      if (!mounted) return;
      final activities = results[0] as List<ActivityItem>;
      final recordings = results[1] as List<RecordingItem>;
      final defaults = results[2] as TypeNotificationDefaults;
      final customMap = await NotificationScheduleService.instance
          .loadCustomOffsetsByItemIds(activities.map((a) => a.id).toList());

      if (!mounted) return;
      setState(() {
        _allActivities = activities;
        _recordings = recordings;
        _typeDefaults = defaults;
        _customOffsetsByItemId = customMap;
        _loading = false;
      });
      _openInitialItemIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _openInitialItemIfNeeded() {
    final targetId = widget.initialItemId;
    if (targetId == null ||
        targetId.isEmpty ||
        targetId == _lastHandledInitialItemId) {
      return;
    }
    final index = _allActivities.indexWhere((item) => item.id == targetId);
    if (index == -1) return;

    _lastHandledInitialItemId = targetId;
    widget.onInitialItemHandled?.call();

    final targetItem = _allActivities[index];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openEditDialog(targetItem);
    });
  }

  Future<void> _onRecordingChanged(String? recordingId) async {
    setState(() {
      _selectedRecordingId = recordingId;
      _loading = true;
      _error = null;
    });
    try {
      final activities = await _api.getActivities(recordingId: recordingId);
      final customMap = await NotificationScheduleService.instance
          .loadCustomOffsetsByItemIds(activities.map((a) => a.id).toList());
      if (!mounted) return;
      setState(() {
        _allActivities = activities;
        _customOffsetsByItemId = customMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<ActivityItem> get _filteredActivities {
    final list = _allActivities.where((item) {
      if (_selectedType != 'all' && item.type != _selectedType) return false;
      final status = item.status ?? 'pending';
      if (_selectedStatus != 'all' && status != _selectedStatus) return false;
      return true;
    }).toList();

    list.sort((a, b) {
      if (_sortBy == 'priority_desc') {
        int rank(String? p) {
          if (p == 'high') return 3;
          if (p == 'medium') return 2;
          if (p == 'low') return 1;
          return 0;
        }

        return rank(b.priority).compareTo(rank(a.priority));
      } else {
        final dateA = '${a.itemDate ?? "9999-12-31"} ${a.itemTime ?? "23:59"}';
        final dateB = '${b.itemDate ?? "9999-12-31"} ${b.itemTime ?? "23:59"}';
        return _sortBy == 'date_asc'
            ? dateA.compareTo(dateB)
            : dateB.compareTo(dateA);
      }
    });

    return list;
  }

  Future<void> _toggleStatus(ActivityItem item) async {
    final currentStatus = item.status ?? 'pending';
    final nextStatus = currentStatus == 'completed' ? 'pending' : 'completed';

    setState(() {
      final idx = _allActivities.indexWhere((a) => a.id == item.id);
      if (idx != -1) {
        _allActivities[idx] = item.copyWith(status: nextStatus);
      }
    });

    try {
      await _api.updateStatus(item, nextStatus);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _allActivities.indexWhere((a) => a.id == item.id);
        if (idx != -1) {
          _allActivities[idx] = item.copyWith(status: currentStatus);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al actualizar: ${e.toString().replaceFirst("Exception: ", "")}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityEditDialog(
        primaryColor: primaryPurple,
        typeDefaults: _typeDefaults,
        item: ActivityDialogData.empty(defaultType: 'task'),
      ),
    );

    if (result != null && mounted) {
      setState(() => _loading = true);
      try {
        final customOffsets = result['notification_offsets'] is List
            ? List<int>.from(result['notification_offsets'] as List)
            : null;
        await _api.createItem(result, customOffsets: customOffsets);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Elemento creado correctamente.'),
              backgroundColor: secondaryGreen,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo crear: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openEditDialog(ActivityItem item) async {
    final currentOffsets =
        _customOffsetsByItemId[item.id] ??
        await NotificationScheduleService.instance.getOffsetsForItem(item.id);
    if (!mounted) return;

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
          date: item.itemDate,
          time: item.itemTime,
          status: item.status ?? 'pending',
          notificationOffsets: currentOffsets,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _loading = true);
      try {
        final customOffsets = result['notification_offsets'] is List
            ? List<int>.from(result['notification_offsets'] as List)
            : null;
        await _api.updateItem(item, result, customOffsets: customOffsets);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cambios guardados.'),
              backgroundColor: secondaryGreen,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al guardar: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteActivity(ActivityItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Eliminar elemento',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          '¿Seguro que deseas eliminar "${item.title}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _loading = true);
      try {
        await _api.deleteItem(item);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Elemento eliminado.')));
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo eliminar: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredActivities;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Actividades y Agenda',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            tooltip: 'Actualizar lista',
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nuevo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: _openCreateDialog,
      ),
      body: Column(
        children: [
          _buildFiltersPanel(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildErrorState()
                : filtered.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildActivityCard(filtered[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_none, size: 18, color: primaryPurple),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedRecordingId,
                    isExpanded: true,
                    hint: const Text(
                      'Todas las notas de voz',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas las notas de voz (Global)'),
                      ),
                      ..._recordings.map(
                        (rec) => DropdownMenuItem<String?>(
                          value: rec.id,
                          child: Text(
                            _recordingLabel(rec),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _onRecordingChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Ordenar por',
                icon: const Icon(Icons.sort, size: 20, color: Colors.black54),
                onSelected: (val) => setState(() => _sortBy = val),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'date_asc',
                    checked: _sortBy == 'date_asc',
                    child: const Text('Fecha más próxima'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'date_desc',
                    checked: _sortBy == 'date_desc',
                    child: const Text('Fecha más lejana'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'priority_desc',
                    checked: _sortBy == 'priority_desc',
                    child: const Text('Prioridad (Alta a Baja)'),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Todos',
                  'all',
                  _selectedType == 'all',
                  (v) => setState(() => _selectedType = v),
                  Colors.black87,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Tareas',
                  'task',
                  _selectedType == 'task',
                  (v) => setState(() => _selectedType = v),
                  primaryPurple,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Recordatorios',
                  'reminder',
                  _selectedType == 'reminder',
                  (v) => setState(() => _selectedType = v),
                  reminderAmber,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Eventos',
                  'event',
                  _selectedType == 'event',
                  (v) => setState(() => _selectedType = v),
                  tertiaryBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Cualquier estado',
                  'all',
                  _selectedStatus == 'all',
                  (v) => setState(() => _selectedStatus = v),
                  Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Pendientes',
                  'pending',
                  _selectedStatus == 'pending',
                  (v) => setState(() => _selectedStatus = v),
                  Colors.orange.shade800,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Completados',
                  'completed',
                  _selectedStatus == 'completed',
                  (v) => setState(() => _selectedStatus = v),
                  secondaryGreen,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Cancelados',
                  'cancelled',
                  _selectedStatus == 'cancelled',
                  (v) => setState(() => _selectedStatus = v),
                  Colors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    bool isSelected,
    ValueChanged<String> onSelected,
    Color activeColor,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      selectedColor: activeColor.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? activeColor : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11.5,
      ),
      side: BorderSide(color: isSelected ? activeColor : Colors.grey.shade300),
      onSelected: (_) => onSelected(value),
    );
  }

  Widget _buildActivityCard(ActivityItem item) {
    final normalizedType = item.type.trim().toLowerCase();
    final isTask = normalizedType == 'task';
    final isReminder = normalizedType == 'reminder';
    final isCompleted = item.status == 'completed';
    final isCancelled = item.status == 'cancelled';

    Color typeColor;
    IconData typeIcon;
    if (isTask) {
      typeColor = primaryPurple;
      typeIcon = Icons.task_alt;
    } else if (isReminder) {
      typeColor = reminderAmber;
      typeIcon = Icons.notifications_none;
    } else {
      typeColor = tertiaryBlue;
      typeIcon = Icons.event_outlined;
    }

    final effectiveOffsets = _typeDefaults.resolveOffsetsForItem(
      itemType: item.type,
      customItemOffsets: _customOffsetsByItemId[item.id],
    );
    final prioLabel = _priorityLabel(item.priority);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCompleted
              ? Colors.grey.shade300
              : typeColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      color: isCompleted ? const Color(0xFFFAFAFA) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _toggleStatus(item),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle
                      : (isCancelled
                            ? Icons.cancel
                            : Icons.radio_button_unchecked),
                  color: isCompleted
                      ? secondaryGreen
                      : (isCancelled ? Colors.red : typeColor),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _openEditDialog(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(typeIcon, size: 11, color: typeColor),
                              const SizedBox(width: 4),
                              Text(
                                _typeLabel(item.type).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (isTask && prioLabel != null && prioLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (item.priority == 'high'
                                          ? Colors.red
                                          : (item.priority == 'medium'
                                                ? Colors.orange
                                                : Colors.teal))
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              prioLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: item.priority == 'high'
                                    ? Colors.red.shade700
                                    : (item.priority == 'medium'
                                          ? Colors.orange.shade800
                                          : Colors.teal),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? Colors.grey : Colors.black87,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (item.description != null &&
                        item.description!.isNotEmpty &&
                        item.description != item.title) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (item.itemDate != null && item.itemDate!.isNotEmpty)
                          _buildMiniTag(
                            Icons.calendar_today_outlined,
                            item.itemDate!,
                            Colors.indigo.shade700,
                          ),
                        if (item.itemTime != null && item.itemTime!.isNotEmpty)
                          _buildMiniTag(
                            Icons.access_time,
                            item.itemTime!,
                            Colors.blueGrey.shade800,
                          ),
                        if (!isCompleted &&
                            !isCancelled &&
                            item.itemDate != null &&
                            item.itemDate!.isNotEmpty)
                          _buildMiniTag(
                            Icons.notifications_active_outlined,
                            effectiveOffsets.isEmpty
                                ? 'Sin avisos'
                                : effectiveOffsets
                                      .map(
                                        (m) =>
                                            NotificationOffset(m).formatLabel(),
                                      )
                                      .join(', '),
                            typeColor,
                          ),
                        _buildMiniTag(
                          Icons.info_outline,
                          _statusLabel(item.status),
                          isCompleted
                              ? secondaryGreen
                              : (isCancelled
                                    ? Colors.red
                                    : Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
              onSelected: (val) {
                if (val == 'edit') _openEditDialog(item);
                if (val == 'delete') _deleteActivity(item);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Eliminar', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTag(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No hay actividades que coincidan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Prueba cambiar los filtros de estado, tipo o nota de voz, o crea un nuevo elemento manualmente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 54, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Error al cargar datos',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
