import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora_lightyear/models/activity_item.dart';

void main() {
  test('maps date and time fields returned by the items query', () {
    final item = ActivityItem.fromJson({
      'id': 'item-1',
      'type': 'event',
      'title': 'Reunión',
      'date': '2026-10-15',
      'time': '09:30',
    });

    expect(item.itemDate, '2026-10-15');
    expect(item.itemTime, '09:30');
  });
}
