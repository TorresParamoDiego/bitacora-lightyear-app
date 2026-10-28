import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/activity_item.dart';
import '../services/activities_api_service.dart';
import '../widgets/activity_edit_dialog.dart';
import 'activity_detail_screen.dart';
class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  final ActivitiesApiService _apiService = ActivitiesApiService();
  late Future<List<ActivityItem>> _futureActivities;
  bool _busy = false;

  // Variables para Filtros y Ordenamiento
  String _searchQuery = '';
  String _filterType = 'all'; // 'all', 'task', 'reminder', 'event'
  String _filterPriority = 'all'; // 'all', 'high', 'medium', 'low'
  String _filterStatus = 'all'; // 'all', 'pending', 'completed', 'overdue'
  String _sortBy =
      'date_asc'; // 'date_asc', 'date_desc', 'priority_desc', 'title_asc'

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  void _loadActivities() {
    final future = _apiService.getActivities();
    setState(() {
      _futureActivities = future;
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      _loadActivities();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(ActivityItem item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityEditDialog(
        item: ActivityDialogData(
          title: item.title,
          description: item.description,
          type: item.type,
          priority: item.priority,
          date: item.itemDate,
          time: item.itemTime,
          status: item.status ?? 'pending',
        ),
      ),
    );

    if (result != null) {
      await _run(
        () => _apiService.updateItem(item, result),
        'Actividad modificada correctamente',
      );
    }
  }

  Future<void> _addNewItem() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityEditDialog(
        item: ActivityDialogData.empty(defaultType: 'task'),
      ),
    );

    if (result != null) {
      await _run(
        () => _apiService.createItem(result),
        'Actividad creada correctamente',
      );
    }
  }

  Future<void> _delete(ActivityItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar actividad'),
        content: Text(
          '¿Seguro que deseas eliminar "${item.title}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() async {
        await _apiService.deleteItem(item);
      }, 'Actividad eliminada');
    }
  }

  bool _isOverdue(ActivityItem item) {
    if (item.status?.toLowerCase() == 'completed') return false;
    if (item.itemDate == null || item.itemDate!.isEmpty) return false;
    try {
      final dateParts = item.itemDate!.split('-');
      if (dateParts.length != 3) return false;
      int year = int.parse(dateParts[0]);
      int month = int.parse(dateParts[1]);
      int day = int.parse(dateParts[2]);

      int hour = 0;
      int minute = 0;
      if (item.itemTime != null && item.itemTime!.isNotEmpty) {
        final timeParts = item.itemTime!.split(':');
        if (timeParts.length >= 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
        }
      }
      final itemDateTime = DateTime(year, month, day, hour, minute);
      return itemDateTime.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filtros y Ordenamiento',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _filterType = 'all';
                              _filterPriority = 'all';
                              _filterStatus = 'all';
                              _sortBy = 'date_asc';
                            });
                            setState(() {});
                          },
                          child: const Text('Restablecer'),
                        ),
                      ],
                    ),
                    const Divider(),

                    // Ordenar por
                    const Text(
                      'Ordenar por',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Fecha (Próximas)'),
                          selected: _sortBy == 'date_asc',
                          onSelected: (_) {
                            setModalState(() => _sortBy = 'date_asc');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Fecha (Lejanas)'),
                          selected: _sortBy == 'date_desc',
                          onSelected: (_) {
                            setModalState(() => _sortBy = 'date_desc');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Prioridad'),
                          selected: _sortBy == 'priority_desc',
                          onSelected: (_) {
                            setModalState(() => _sortBy = 'priority_desc');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Título (A-Z)'),
                          selected: _sortBy == 'title_asc',
                          onSelected: (_) {
                            setModalState(() => _sortBy = 'title_asc');
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filtro Estatus
                    const Text(
                      'Estatus',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _filterStatus == 'all',
                          onSelected: (_) {
                            setModalState(() => _filterStatus = 'all');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Pendientes'),
                          selected: _filterStatus == 'pending',
                          onSelected: (_) {
                            setModalState(() => _filterStatus = 'pending');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Completadas'),
                          selected: _filterStatus == 'completed',
                          onSelected: (_) {
                            setModalState(() => _filterStatus = 'completed');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Vencidas'),
                          selected: _filterStatus == 'overdue',
                          onSelected: (_) {
                            setModalState(() => _filterStatus = 'overdue');
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filtro Tipo
                    const Text(
                      'Tipo de Actividad',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _filterType == 'all',
                          onSelected: (_) {
                            setModalState(() => _filterType = 'all');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Tareas'),
                          selected: _filterType == 'task',
                          onSelected: (_) {
                            setModalState(() => _filterType = 'task');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Recordatorios'),
                          selected: _filterType == 'reminder',
                          onSelected: (_) {
                            setModalState(() => _filterType = 'reminder');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Eventos'),
                          selected: _filterType == 'event',
                          onSelected: (_) {
                            setModalState(() => _filterType = 'event');
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filtro Prioridad
                    const Text(
                      'Prioridad',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todas'),
                          selected: _filterPriority == 'all',
                          onSelected: (_) {
                            setModalState(() => _filterPriority = 'all');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Alta'),
                          selected: _filterPriority == 'high',
                          onSelected: (_) {
                            setModalState(() => _filterPriority = 'high');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Media'),
                          selected: _filterPriority == 'medium',
                          onSelected: (_) {
                            setModalState(() => _filterPriority = 'medium');
                            setState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Baja'),
                          selected: _filterPriority == 'low',
                          onSelected: (_) {
                            setModalState(() => _filterPriority = 'low');
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Aplicar Filtros'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<ActivityItem> _applyFiltersAndSort(List<ActivityItem> rawItems) {
    return rawItems.where((item) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final titleMatches = item.title.toLowerCase().contains(q);
        final descMatches = (item.description ?? '').toLowerCase().contains(q);
        if (!titleMatches && !descMatches) return false;
      }

      if (_filterType != 'all' && item.type.toLowerCase() != _filterType) {
        return false;
      }

      if (_filterPriority != 'all' &&
          (item.priority ?? '').toLowerCase() != _filterPriority) {
        return false;
      }

      final completed = item.status?.toLowerCase() == 'completed';
      final overdue = _isOverdue(item);

      if (_filterStatus == 'completed' && !completed) return false;
      if (_filterStatus == 'pending' && (completed || overdue)) return false;
      if (_filterStatus == 'overdue' && !overdue) return false;

      return true;
    }).toList()..sort((a, b) {
      switch (_sortBy) {
        case 'date_asc':
          final dateA =
              '${a.itemDate ?? '9999-99-99'} ${a.itemTime ?? '23:59'}';
          final dateB =
              '${b.itemDate ?? '9999-99-99'} ${b.itemTime ?? '23:59'}';
          return dateA.compareTo(dateB);

        case 'date_desc':
          final dateA =
              '${a.itemDate ?? '0000-00-00'} ${a.itemTime ?? '00:00'}';
          final dateB =
              '${b.itemDate ?? '0000-00-00'} ${b.itemTime ?? '00:00'}';
          return dateB.compareTo(dateA);

        case 'priority_desc':
          final map = {'high': 3, 'medium': 2, 'low': 1};
          final weightA = map[(a.priority ?? '').toLowerCase()] ?? 0;
          final weightB = map[(b.priority ?? '').toLowerCase()] ?? 0;
          return weightB.compareTo(weightA);

        case 'title_asc':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());

        default:
          return 0;
      }
    });
  }

  Color _typeColor(String type) => switch (type.toLowerCase()) {
    'event' => Colors.purple,
    'reminder' => Colors.green,
    'task' => Colors.blue,
    _ => Colors.grey,
  };

  Color _priorityColor(String? p) => switch (p?.toLowerCase()) {
    'high' => Colors.red,
    'medium' => Colors.orange,
    'low' => Colors.blue,
    _ => Colors.grey,
  };

  String _type(String type) => switch (type.toLowerCase()) {
    'task' => 'Tarea',
    'reminder' => 'Recordatorio',
    'event' => 'Evento',
    _ => 'Actividad',
  };

  String _priority(String? p) => switch (p?.toLowerCase()) {
    'high' => 'Alta',
    'medium' => 'Media',
    'low' => 'Baja',
    _ => 'Sin prioridad',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mis Actividades'),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadActivities),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _addNewItem,
      tooltip: 'Agregar nueva actividad',
      child: const Icon(Icons.add),
    ),
    body: Stack(
      children: [
        Column(
          children: [
            // Barra de Búsqueda y Filtros
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar palabras clave...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setState(() => _searchQuery = ''),
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (val) =>
                          setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Opciones de filtro',
                    icon: const Icon(Icons.tune),
                    onPressed: _showFilterBottomSheet,
                  ),
                ],
              ),
            ),

            // Contenido de Actividades
            Expanded(
              child: FutureBuilder<List<ActivityItem>>(
                future: _futureActivities,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const Text(
                            'No fue posible recuperar las actividades',
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadActivities,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    );
                  }

                  final rawItems = snapshot.data ?? [];

                  if (!kIsWeb) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {}
                    });
                  }

                  final items = _applyFiltersAndSort(rawItems);

                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        rawItems.isEmpty
                            ? 'No hay actividades registradas'
                            : 'No hay actividades que coincidan con los filtros',
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final completed =
                          item.status?.toLowerCase() == 'completed';
                      final overdue = _isOverdue(item);

                      return Card(
                        elevation: overdue ? 4 : 1,
                        color: overdue
                            ? Colors.red.shade100
                            : (completed ? Colors.grey.shade100 : null),
                        margin: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: overdue
                              ? BorderSide(
                                  color: Colors.red.shade400,
                                  width: 1.5,
                                )
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ActivityDetailScreen(itemId: item.id!), // Asegúrate de que el id no sea nulo
                              ),
                            ).then((_) => _loadActivities()); // Recarga al volver si hubo cambios
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: IconButton(
                            tooltip: completed
                                ? 'Marcar como pendiente'
                                : 'Marcar como completada',
                            icon: Icon(
                              completed
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: completed
                                  ? Colors.green
                                  : (overdue
                                        ? Colors.red.shade700
                                        : Theme.of(
                                            context,
                                          ).colorScheme.primary),
                              size: 28,
                            ),
                            onPressed: () {
                              final newStatus = completed
                                  ? 'pending'
                                  : 'completed';
                              final msg = completed
                                  ? 'Tarea marcada como pendiente'
                                  : 'Tarea marcada como completada';
                              _run(
                                () => _apiService.updateStatus(item, newStatus),
                                msg,
                              );
                            },
                          ),
                          title: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: overdue ? Colors.red.shade900 : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _typeColor(
                                        item.type,
                                      ).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _typeColor(item.type),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      _type(item.type),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _typeColor(item.type),
                                      ),
                                    ),
                                  ),
                                  if (item.priority != null &&
                                      item.priority!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _priorityColor(
                                          item.priority,
                                        ).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _priorityColor(item.priority),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        _priority(item.priority),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _priorityColor(item.priority),
                                        ),
                                      ),
                                    ),
                                  if (overdue)
                                    InkWell(
                                      onTap: () => _run(
                                        () => _apiService.updateStatus(
                                          item,
                                          'completed',
                                        ),
                                        'Actividad marcada como completada',
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.red,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              size: 13,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'Vencida · Marcar completada',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if ((item.description ?? '').isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  item.description!,
                                  style: TextStyle(
                                    color: overdue
                                        ? Colors.red.shade800
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                              if (item.itemDate != null ||
                                  item.itemTime != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: overdue
                                          ? Colors.red.shade700
                                          : Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      [item.itemDate, item.itemTime]
                                          .where(
                                            (v) => v != null && v.isNotEmpty,
                                          )
                                          .join(' · '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: overdue
                                            ? Colors.red.shade700
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Opciones de actividad',
                            onSelected: (choice) {
                              if (choice == 'completed' ||
                                  choice == 'pending') {
                                _run(
                                  () => _apiService.updateStatus(item, choice),
                                  choice == 'completed'
                                      ? 'Tarea marcada como completada'
                                      : 'Tarea marcada como pendiente',
                                );
                              }
                              if (choice == 'edit') _edit(item);
                              if (choice == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => [
                              if (!completed)
                                const PopupMenuItem(
                                  value: 'completed',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.check),
                                    title: Text('Marcar como completada'),
                                  ),
                                ),
                              if (completed)
                                const PopupMenuItem(
                                  value: 'pending',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.undo),
                                    title: Text('Marcar como pendiente'),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.edit),
                                  title: Text('Modificar'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Borrar'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        if (_busy)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}
