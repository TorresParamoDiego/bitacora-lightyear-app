import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora_lightyear/models/extracted_item.dart';

void main() {
  group('ExtractedItem Model Tests', () {
    test('Parsea correctamente JSON estandarizado con todos los campos', () {
      final json = {
        'type': 'task',
        'title': 'Entregar el proyecto',
        'description': 'Entrega del proyecto de bases de datos',
        'priority': 'high',
        'date': '2026-10-17',
        'time': '14:30',
        'status': 'pending',
      };

      final item = ExtractedItem.fromJson(json);

      expect(item.type, 'task');
      expect(item.isTask, isTrue);
      expect(item.title, 'Entregar el proyecto');
      expect(item.description, 'Entrega del proyecto de bases de datos');
      expect(item.priority, 'high');
      expect(item.priorityLabel, 'Alta');
      expect(item.date, '2026-10-17');
      expect(item.time, '14:30');
      expect(item.status, 'pending');
      expect(item.statusLabel, 'Pendiente');
    });

    test('Maneja campos nulos sin convertirlos en texto "null"', () {
      final json = {
        'type': 'reminder',
        'title': 'Cumpleaños de Ana',
        'description': 'Tener presente el cumpleaños de Ana',
        'priority': null,
        'date': '2026-11-20',
        'time': null,
        'status': 'pending',
      };

      final item = ExtractedItem.fromJson(json);

      expect(item.type, 'reminder');
      expect(item.isReminder, isTrue);
      expect(item.priority, isNull);
      expect(item.priorityLabel, isNull);
      expect(item.time, isNull);
      expect(item.date, '2026-11-20');
      expect(item.status, 'pending');
    });

    test('Limpia valores string "null" o "None" para asegurar que sean null real', () {
      final json = {
        'type': 'event',
        'title': 'Clase de natación',
        'description': 'Asistí a clase de natación',
        'priority': 'null',
        'date': '2026-10-10',
        'time': 'None',
        'status': 'completed',
      };

      final item = ExtractedItem.fromJson(json);

      expect(item.type, 'event');
      expect(item.isEvent, isTrue);
      expect(item.priority, isNull);
      expect(item.time, isNull);
      expect(item.status, 'completed');
      expect(item.statusLabel, 'Completado');
    });

    test('toJson incluye siempre los 7 campos estandarizados', () {
      final item = ExtractedItem(
        type: 'task',
        title: 'Comprar materiales',
        description: 'Papel y tinta',
        priority: null,
        date: null,
        time: null,
        status: 'pending',
      );

      final json = item.toJson();

      expect(json.containsKey('type'), isTrue);
      expect(json.containsKey('title'), isTrue);
      expect(json.containsKey('description'), isTrue);
      expect(json.containsKey('priority'), isTrue);
      expect(json.containsKey('date'), isTrue);
      expect(json.containsKey('time'), isTrue);
      expect(json.containsKey('status'), isTrue);

      expect(json['priority'], isNull);
      expect(json['date'], isNull);
      expect(json['time'], isNull);
    });

    test('copyWith actualiza campos correctamente incluyendo nulabilidad', () {
      final original = ExtractedItem(
        type: 'task',
        title: 'Original',
        description: 'Desc',
        priority: 'high',
        date: '2026-10-13',
        status: 'pending',
      );

      final updated = original.copyWith(
        title: 'Modificado',
        priority: () => null,
      );

      expect(updated.title, 'Modificado');
      expect(updated.priority, isNull);
      expect(updated.date, '2026-10-13');
    });
  });
}
