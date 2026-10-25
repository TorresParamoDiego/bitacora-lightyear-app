import 'package:flutter/material.dart';

/// Interfaz para abstraer los modelos (ActivityItem y ExtractedItem)
class ActivityDialogData {
  final String title;
  final String? description;
  final String type;
  final String? priority;
  final String? date;
  final String? time;
  final String status;

  ActivityDialogData({
    required this.title,
    this.description,
    required this.type,
    this.priority,
    this.date,
    this.time,
    required this.status,
  });
  factory ActivityDialogData.empty({String defaultType = 'task'}) {
    return ActivityDialogData(
      title: '',
      description: '',
      type: defaultType,
      priority: null,
      date: null,
      time: null,
      status: 'pending',
    );
  }
}

class ActivityEditDialog extends StatefulWidget {
  final ActivityDialogData item;
  final Color primaryColor;

  const ActivityEditDialog({
    super.key,
    required this.item,
    this.primaryColor = const Color(0xFF5C4EE5),
  });

  @override
  State<ActivityEditDialog> createState() => _ActivityEditDialogState();
}

class _ActivityEditDialogState extends State<ActivityEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descController;

  late String _selectedType;
  late String? _selectedPriority;
  late String? _selectedDate;
  late String? _selectedTime;
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _descController = TextEditingController(text: widget.item.description ?? '');

    _selectedType = widget.item.type;
    _selectedPriority = widget.item.priority;
    _selectedDate = widget.item.date;
    _selectedTime = widget.item.time;
    _selectedStatus = widget.item.status;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  IconData _getTypeIcon() {
    switch (_selectedType) {
      case 'task':
        return Icons.task_alt;
      case 'reminder':
        return Icons.alarm;
      case 'event':
      default:
        return Icons.event;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    DateTime initial = now;
    if (_selectedDate != null && _selectedDate!.isNotEmpty) {
      final parsed = DateTime.tryParse(_selectedDate!);
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
      setState(() {
        _selectedDate = '${picked.year}-$m-$d';
      });
    }
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    if (_selectedTime != null && _selectedTime!.isNotEmpty) {
      final parts = _selectedTime!.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]) ?? 12;
        final m = int.tryParse(parts[1]) ?? 0;
        initial = TimeOfDay(hour: h, minute: m);
      }
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() {
        _selectedTime = '$h:$m';
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty) return;

    Navigator.of(context).pop({
      'title': newTitle,
      'description': _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      'type': _selectedType,
      'priority': _selectedType == 'task' ? _selectedPriority : null,
      'date': _selectedDate,
      'time': _selectedTime,
      'status': _selectedStatus,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 480),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Icon(
            _getTypeIcon(),
            color: widget.primaryColor,
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
          child: Form(
            key: _formKey,
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
                  initialValue: _selectedType,
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
                      child: Text('Tarea (actividad a realizar)'),
                    ),
                    DropdownMenuItem(
                      value: 'reminder',
                      child: Text('Recordatorio (información a tener presente)'),
                    ),
                    DropdownMenuItem(
                      value: 'event',
                      child: Text('Evento (cita, reunión o actividad)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedType = val;
                        if (_selectedType != 'task') {
                          _selectedPriority = null;
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
                TextFormField(
                  controller: _titleController,
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'El título es obligatorio'
                      : null,
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
                TextFormField(
                  controller: _descController,
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

                // Prioridad (solo tareas)
                if (_selectedType == 'task') ...[
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
                    initialValue: ['high', 'medium', 'low'].contains(_selectedPriority)
                        ? _selectedPriority
                        : null,
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
                    onChanged: (val) => setState(() => _selectedPriority = val),
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
                          _selectedDate ?? 'Sin fecha asignada',
                          style: TextStyle(
                            color: _selectedDate != null
                                ? Colors.black87
                                : Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: _pickDate,
                      ),
                    ),
                    if (_selectedDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        tooltip: 'Borrar fecha',
                        onPressed: () => setState(() => _selectedDate = null),
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
                          _selectedTime ?? 'Sin hora asignada',
                          style: TextStyle(
                            color: _selectedTime != null
                                ? Colors.black87
                                : Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: _pickTime,
                      ),
                    ),
                    if (_selectedTime != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        tooltip: 'Borrar hora',
                        onPressed: () => setState(() => _selectedTime = null),
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
                  initialValue: _selectedStatus,
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
                      setState(() => _selectedStatus = val);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _save,
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
  }
}