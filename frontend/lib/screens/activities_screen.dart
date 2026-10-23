import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/activity_item.dart';
import '../services/activities_api_service.dart';
import 'register_screen.dart';
import '../services/reminder_notification_service.dart';

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});
  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  final ActivitiesApiService _apiService = ActivitiesApiService();
  late Future<List<ActivityItem>> _futureActivities;
  bool _busy = false;

  @override
  void initState() { super.initState(); _loadActivities(); }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _loadActivities();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _edit(ActivityItem item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ActivityEditDialog(item: item),
    );
    if (result != null) await _run(() => _apiService.updateItem(item, result), 'Actividad modificada correctamente');
  }

  Future<void> _delete(ActivityItem item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eliminar actividad'),
      content: Text('¿Seguro que deseas eliminar "${item.title}"? Esta acción no se puede deshacer.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar'))],
    ));
    if (confirmed == true) await _run(() async { await _apiService.deleteItem(item); await ReminderNotificationService.instance.cancelForItem(item.id); }, 'Actividad eliminada');
  }

  String _type(String type) => switch (type.toLowerCase()) {'task' => 'Tarea', 'reminder' => 'Recordatorio', 'event' => 'Evento', _ => 'Actividad'};
  String _priority(String? p) => switch (p?.toLowerCase()) {'high' => 'Alta', 'medium' => 'Media', 'low' => 'Baja', _ => 'Sin prioridad'};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis Actividades'), actions: [IconButton(tooltip: 'Crear cuenta', icon: const Icon(Icons.person_add_alt_1), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()))), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadActivities)]),
    body: Stack(children: [
      FutureBuilder<List<ActivityItem>>(future: _futureActivities, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, size: 48, color: Colors.red), const Text('No fue posible recuperar las actividades'), const SizedBox(height: 12), ElevatedButton(onPressed: _loadActivities, child: const Text('Reintentar'))]));
        final items = snapshot.data ?? [];
        if (!kIsWeb) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ReminderNotificationService.instance.sync(items);
          });
        }
        if (items.isEmpty) return const Center(child: Text('No hay actividades registradas'));
        return ListView.builder(padding: const EdgeInsets.all(8), itemCount: items.length, itemBuilder: (context, index) {
          final item = items[index];
          final completed = item.status?.toLowerCase() == 'completed';
          return Card(margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: ListTile(
            leading: Icon(completed ? Icons.check_circle : Icons.radio_button_unchecked, color: completed ? Colors.green : Theme.of(context).colorScheme.primary),
            title: Text(item.title, style: TextStyle(fontWeight: FontWeight.bold, decoration: completed ? TextDecoration.lineThrough : null)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_type(item.type)} · ${_priority(item.priority)} · ${completed ? "Completada" : "Pendiente"}'),
              if ((item.description ?? '').isNotEmpty) Text(item.description!),
              if (item.itemDate != null || item.itemTime != null) Text([item.itemDate, item.itemTime].where((v) => v != null && v.isNotEmpty).join(' · ')),
            ]),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(tooltip: 'Opciones de actividad', onSelected: (choice) {
              if (choice == 'completed' || choice == 'pending') _run(() => _apiService.updateStatus(item, choice), choice == 'completed' ? 'Tarea marcada como completada' : 'Tarea marcada como pendiente');
              if (choice == 'edit') _edit(item);
              if (choice == 'delete') _delete(item);
            }, itemBuilder: (_) => [
              if (!completed) const PopupMenuItem(value: 'completed', child: ListTile(dense: true, leading: Icon(Icons.check), title: Text('Marcar como completada'))),
              if (completed) const PopupMenuItem(value: 'pending', child: ListTile(dense: true, leading: Icon(Icons.undo), title: Text('Marcar como pendiente'))),
              const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit), title: Text('Modificar'))),
              const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Borrar'))),
            ]),
          ));
        });
      }),
      if (_busy) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
    ]),
  );
}

class _ActivityEditDialog extends StatefulWidget {
  const _ActivityEditDialog({required this.item});

  final ActivityItem item;

  @override
  State<_ActivityEditDialog> createState() => _ActivityEditDialogState();
}

class _ActivityEditDialogState extends State<_ActivityEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _priority;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
    _description = TextEditingController(text: widget.item.description ?? '');
    _date = TextEditingController(text: widget.item.itemDate ?? '');
    _time = TextEditingController(text: widget.item.itemTime ?? '');
    _priority = TextEditingController(text: widget.item.priority ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _date.dispose();
    _time.dispose();
    _priority.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(context, {
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'type': widget.item.type,
      'priority': _priority.text.isEmpty ? null : _priority.text,
      'date': _date.text.trim().isEmpty ? null : _date.text.trim(),
      'time': _time.text.trim().isEmpty ? null : _time.text.trim(),
      'status': widget.item.status == 'completed' ? 'completed' : 'pending',
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Modificar actividad'),
    content: Form(key: _formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Título'), validator: (value) => value == null || value.trim().isEmpty ? 'El título es obligatorio' : null),
      TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Descripción')),
      TextFormField(controller: _date, decoration: const InputDecoration(labelText: 'Fecha (AAAA-MM-DD)')),
      TextFormField(controller: _time, decoration: const InputDecoration(labelText: 'Hora (HH:mm)')),
      DropdownButtonFormField<String>(initialValue: ['high', 'medium', 'low'].contains(_priority.text) ? _priority.text : null, decoration: const InputDecoration(labelText: 'Prioridad'), items: const [
        DropdownMenuItem(value: 'high', child: Text('Alta')), DropdownMenuItem(value: 'medium', child: Text('Media')), DropdownMenuItem(value: 'low', child: Text('Baja')),
      ], onChanged: (value) => _priority.text = value ?? ''),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}
