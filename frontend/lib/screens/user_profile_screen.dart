import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_preferences.dart';
import '../services/auth_service.dart';
import '../services/notification_schedule_service.dart';
import 'login_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  TypeNotificationDefaults _defaults = TypeNotificationDefaults();
  bool _loadingDefaults = true;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final loaded = await NotificationScheduleService.instance.loadTypeDefaults();
    if (!mounted) return;
    setState(() {
      _defaults = loaded;
      _loadingDefaults = false;
    });
  }

  Future<void> _openTypeDefaultEditor(String itemType, String titleLabel) async {
    final currentOffsets = List<int>.from(_defaults.offsetsForType(itemType));
    final amountController = TextEditingController(text: '30');
    NotificationUnit selectedUnit = NotificationUnit.minutes;

    final updatedOffsets = await showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void addMinutes(int mins) {
              if (mins < 0 || currentOffsets.contains(mins)) return;
              setModalState(() {
                currentOffsets.add(mins);
                currentOffsets.sort((a, b) => b.compareTo(a));
              });
            }

            void addCustom() {
              final raw = int.tryParse(amountController.text.trim());
              if (raw == null || raw < 0) return;
              addMinutes(NotificationOffset.fromValue(raw, selectedUnit).minutes);
            }

            return AlertDialog(
              title: Text('Default: $titleLabel'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Avisos programados por defecto para este tipo:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: currentOffsets.map((m) {
                        return Chip(
                          label: Text(
                            NotificationOffset(m).formatLabel(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onDeleted: () {
                            setModalState(() => currentOffsets.remove(m));
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          label: const Text('+ 1 sem', style: TextStyle(fontSize: 11)),
                          onPressed: () => addMinutes(10080),
                        ),
                        ActionChip(
                          label: const Text('+ 2 días', style: TextStyle(fontSize: 11)),
                          onPressed: () => addMinutes(2880),
                        ),
                        ActionChip(
                          label: const Text('+ 1 día', style: TextStyle(fontSize: 11)),
                          onPressed: () => addMinutes(1440),
                        ),
                        ActionChip(
                          label: const Text('+ 1 hora', style: TextStyle(fontSize: 11)),
                          onPressed: () => addMinutes(60),
                        ),
                        ActionChip(
                          label: const Text('+ 30 min', style: TextStyle(fontSize: 11)),
                          onPressed: () => addMinutes(30),
                        ),
                        ActionChip(
                          label: const Text('+ Al momento', style: TextStyle(fontSize: 11)),
                          onPressed: () => addMinutes(0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<NotificationUnit>(
                            value: selectedUnit,
                            isDense: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: NotificationUnit.values
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(
                                      u.label,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (u) {
                              if (u != null) {
                                setModalState(() => selectedUnit = u);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add),
                          onPressed: addCustom,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, currentOffsets),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();

    if (updatedOffsets != null && mounted) {
      try {
        // Persiste el esquema default por tipo en Supabase para el usuario actual.
        await NotificationScheduleService.instance.saveTypeDefault(
          itemType: itemType,
          offsetMinutes: updatedOffsets,
        );
        setState(() {
          _defaults = _defaults.withOffsetsForType(itemType, updatedOffsets);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Default actualizado para $titleLabel')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar el default: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Estás seguro de que deseas salir? Dejarás de recibir notificaciones en este dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await AuthService().signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }

  Widget _buildTypeDefaultTile(String itemType, String label, IconData icon) {
    final offsets = _defaults.offsetsForType(itemType);
    final summary = offsets.isEmpty
        ? 'Sin avisos por defecto'
        : offsets.map((m) => NotificationOffset(m).formatLabel()).join(', ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF5C4EE5)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(summary, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _openTypeDefaultEditor(itemType, label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 44,
              backgroundColor: Color(0xFF5C4EE5),
              child: Icon(Icons.person, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              user?.email ?? 'Usuario de pruebas',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${user?.id ?? "00000000-0000-0000-0000-000000000002"}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Notificaciones por defecto',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            if (_loadingDefaults)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              )
            else ...[
              _buildTypeDefaultTile('task', 'Tareas', Icons.task_alt),
              _buildTypeDefaultTile('reminder', 'Recordatorios', Icons.alarm),
              _buildTypeDefaultTile('event', 'Eventos', Icons.event),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
                onPressed: () => _handleLogout(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}