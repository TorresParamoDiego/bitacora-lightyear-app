import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bitacora_lightyear/models/extracted_item.dart';
import 'package:bitacora_lightyear/services/analysis_api_service.dart';

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('AnalysisApiService Tests', () {
    test('analyzeTranscription devuelve lista de ExtractedItem correctamente', () async {
      final fakeClient = FakeHttpClient((request) async {
        expect(request.url.path, '/api/analysis');
        expect(request.method, 'POST');

        final responseJson = {
          'items': [
            {
              'type': 'task',
              'title': 'Entregar el proyecto',
              'description': 'Entrega del proyecto de bases de datos',
              'priority': 'high',
              'date': '2026-10-17',
              'time': null,
              'status': 'pending',
            },
            {
              'type': 'reminder',
              'title': 'Cumpleaños de Ana',
              'description': 'Tener presente el cumpleaños de Ana',
              'priority': null,
              'date': '2026-11-20',
              'time': null,
              'status': 'pending',
            },
          ]
        };

        return http.Response(jsonEncode(responseJson), 200, headers: {'content-type': 'application/json'});
      });

      final service = AnalysisApiService(baseUrl: 'http://test-server:8000', client: fakeClient);
      final items = await service.analyzeTranscription('Texto de prueba', referenceDate: '2026-10-13');

      expect(items.length, 2);
      expect(items[0].type, 'task');
      expect(items[0].priority, 'high');
      expect(items[1].type, 'reminder');
      expect(items[1].priority, isNull);
    });

    test('analyzeTranscription maneja lista vacía para charla casual', () async {
      final fakeClient = FakeHttpClient((request) async {
        return http.Response(jsonEncode({'items': []}), 200, headers: {'content-type': 'application/json'});
      });

      final service = AnalysisApiService(baseUrl: 'http://test-server:8000', client: fakeClient);
      final items = await service.analyzeTranscription('Hola probando uno dos');

      expect(items, isEmpty);
    });

    test('saveConfirmedItems envía lista y devuelve cantidad guardada', () async {
      final fakeClient = FakeHttpClient((request) async {
        expect(request.url.path, '/api/items');
        expect(request.method, 'POST');

        return http.Response(
          jsonEncode({'saved_count': 2, 'message': 'Guardados correctamente'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisApiService(baseUrl: 'http://test-server:8000', client: fakeClient);
      final itemsToSave = [
        ExtractedItem(type: 'task', title: 'Tarea 1', description: 'Desc 1'),
        ExtractedItem(type: 'event', title: 'Evento 1', description: 'Desc 2'),
      ];

      final count = await service.saveConfirmedItems(itemsToSave);
      expect(count, 2);
    });

    test('Lanza AnalysisApiException cuando el backend responde error', () async {
      final fakeClient = FakeHttpClient((request) async {
        return http.Response(jsonEncode({'detail': 'Error interno de prueba'}), 500);
      });

      final service = AnalysisApiService(baseUrl: 'http://test-server:8000', client: fakeClient);

      expect(
        () => service.analyzeTranscription('Texto con error'),
        throwsA(isA<AnalysisApiException>()),
      );
    });
  });
}
