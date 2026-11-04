import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora_lightyear/models/activity_item.dart';
import 'package:bitacora_lightyear/services/reminder_schedule.dart';

void main() {
  group('US8 - Recordatorios y Alertas de Fechas Límite', () {
    final sampleTask = ActivityItem(
      id: 'task-123',
      type: 'task',
      title: 'Entrega de informe',
      description: 'Informe final de proyecto',
      priority: 'high',
      itemDate: '2026-11-20',
      itemTime: '15:00',
      status: 'pending',
    );

    final sampleEvent = ActivityItem(
      id: 'event-456',
      type: 'event',
      title: 'Reunión de equipo',
      itemDate: '2026-11-20',
      itemTime: '10:00',
      status: 'pending',
    );

    test('Criterio 1: genera avisos previos configurados (1 día y 30 minutos)', () {
      final triggers = ReminderSchedule.buildTriggers(sampleTask);
      expect(triggers.length, 3);

      final oneDayTrigger = triggers.firstWhere((t) => t.kind == ReminderKind.oneDayBefore);
      final thirtyMinTrigger = triggers.firstWhere((t) => t.kind == ReminderKind.thirtyMinutesBefore);

      final expectedDue = DateTime(2026, 11, 20, 15, 0);
      expect(oneDayTrigger.fireAt, expectedDue.subtract(const Duration(days: 1)));
      expect(thirtyMinTrigger.fireAt, expectedDue.subtract(const Duration(minutes: 30)));

      expect(oneDayTrigger.title, contains('mañana'));
      expect(oneDayTrigger.body, contains('Entrega de informe'));
      expect(thirtyMinTrigger.title, contains('30 minutos'));
    });

    test('Criterio 2: genera alerta inmediata al cumplirse la fecha y hora (vencimiento)', () {
      final taskTriggers = ReminderSchedule.buildTriggers(sampleTask);
      final dueTrigger = taskTriggers.firstWhere((t) => t.kind == ReminderKind.due);

      final expectedDue = DateTime(2026, 11, 20, 15, 0);
      expect(dueTrigger.fireAt, expectedDue);
      expect(dueTrigger.isDueAlert, isTrue);
      expect(dueTrigger.title, '¡Tarea vencida!');
      expect(dueTrigger.body, contains('La fecha límite de "Entrega de informe" se cumplió'));

      // Para eventos el mensaje es acorde al inicio
      final eventTriggers = ReminderSchedule.buildTriggers(sampleEvent);
      final eventDueTrigger = eventTriggers.firstWhere((t) => t.kind == ReminderKind.due);
      expect(eventDueTrigger.title, '¡Tu evento comienza ahora!');
    });

    test('Criterio 3: los triggers y claves asocian el itemId para la redirección al detalle', () {
      final triggers = ReminderSchedule.buildTriggers(sampleTask);
      for (final trigger in triggers) {
        expect(trigger.itemId, 'task-123');
        expect(trigger.key, startsWith('task-123_'));
      }
    });

    test('Criterio 4: al completar antes del vencimiento cancela los recordatorios', () {
      // 1. Actividades cerradas no generan disparos pendientes
      final completedTask = sampleTask.copyWith(status: 'completed');
      expect(ReminderSchedule.buildTriggers(completedTask), isEmpty);

      final cancelledTask = sampleTask.copyWith(status: 'cancelled');
      expect(ReminderSchedule.buildTriggers(cancelledTask), isEmpty);

      // 2. Las banderas del servidor se marcan como enviadas para que no mande más push
      final flagsCompleted = ReminderSchedule.notificationFlagsFor(
        itemDate: sampleTask.itemDate,
        itemTime: sampleTask.itemTime,
        status: 'completed',
        now: DateTime(2026, 11, 10, 12, 0), // antes del vencimiento
      );

      expect(flagsCompleted['notification_1d_sent'], isTrue);
      expect(flagsCompleted['notification_30m_sent'], isTrue);
      expect(flagsCompleted['notification_due_sent'], isTrue);
    });

    test('Calcula banderas correctamente para tareas pendientes según fecha actual', () {
      final dueAt = DateTime(2026, 11, 20, 15, 0);

      // Tiempo antes de cualquier recordatorio (más de 1 día antes)
      final earlyFlags = ReminderSchedule.notificationFlagsFor(
        itemDate: '2026-11-20',
        itemTime: '15:00',
        status: 'pending',
        now: dueAt.subtract(const Duration(days: 2)),
      );
      expect(earlyFlags['notification_1d_sent'], isFalse);
      expect(earlyFlags['notification_30m_sent'], isFalse);
      expect(earlyFlags['notification_due_sent'], isFalse);

      // Tiempo entre 1 día y 30 minutos antes (ya pasó el aviso de 1 día)
      final midFlags = ReminderSchedule.notificationFlagsFor(
        itemDate: '2026-11-20',
        itemTime: '15:00',
        status: 'pending',
        now: dueAt.subtract(const Duration(hours: 2)),
      );
      expect(midFlags['notification_1d_sent'], isTrue);
      expect(midFlags['notification_30m_sent'], isFalse);
      expect(midFlags['notification_due_sent'], isFalse);
    });

    test('dueDateTimeOf usa 09:00 AM como hora por defecto si no se especifica hora', () {
      final due = ReminderSchedule.dueDateTimeOf(itemDate: '2026-11-25');
      expect(due, isNotNull);
      expect(due!.year, 2026);
      expect(due.month, 11);
      expect(due.day, 25);
      expect(due.hour, ReminderSchedule.defaultHour);
      expect(due.minute, ReminderSchedule.defaultMinute);
    });
  });
}
