import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bitacora_lightyear/models/extracted_item.dart';
import 'package:bitacora_lightyear/screens/analysis_review_screen.dart';
import 'package:bitacora_lightyear/services/analysis_api_service.dart';

class MockSaveClient extends http.BaseClient {
  bool saveCalled = false;
  int savedItemsCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/api/items' && request.method == 'POST') {
      saveCalled = true;
      final bodyStr = await request.finalize().bytesToString();
      final decoded = jsonDecode(bodyStr);
      final items = decoded['items'] as List;
      savedItemsCount = items.length;

      final resBody = jsonEncode({
        'saved_count': savedItemsCount,
        'message': 'Guardado correctamente',
        'items': items,
      });

      return http.StreamedResponse(
        Stream.value(utf8.encode(resBody)),
        201,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
  }
}

void main() {
  group('AnalysisReviewScreen Widget Tests', () {
    late List<ExtractedItem> sampleItems;
    late MockSaveClient mockClient;
    late AnalysisApiService fakeApiService;

    setUp(() {
      sampleItems = [
        ExtractedItem(
          type: 'task',
          title: 'Entregar el proyecto',
          description: 'Entrega del proyecto de bases de datos',
          priority: 'high',
          date: '2026-10-17',
          time: null,
          status: 'pending',
        ),
        ExtractedItem(
          type: 'reminder',
          title: 'Cumpleaños de Ana',
          description: 'Tener presente el cumpleaños de Ana',
          priority: null,
          date: '2026-11-20',
          time: null,
          status: 'pending',
        ),
        ExtractedItem(
          type: 'event',
          title: 'Clase de natación',
          description: 'Asistí a clase de natación',
          priority: null,
          date: '2026-10-10',
          time: null,
          status: 'completed',
        ),
      ];

      mockClient = MockSaveClient();
      fakeApiService = AnalysisApiService(baseUrl: 'http://test-server:8000', client: mockClient);
    });

    Widget createWidgetUnderTest() {
      return MaterialApp(
        home: AnalysisReviewScreen(
          initialItems: sampleItems,
          apiService: fakeApiService,
        ),
      );
    }

    testWidgets('Muestra los resultados en bloques visuales diferenciados por tipo', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Verificar títulos de elementos presentes
      expect(find.text('Entregar el proyecto'), findsOneWidget);
      expect(find.text('Cumpleaños de Ana'), findsOneWidget);
      expect(find.text('Clase de natación'), findsOneWidget);

      // Verificar etiquetas visuales por tipo
      expect(find.text('TAREA'), findsOneWidget);
      expect(find.text('RECORDATORIO'), findsOneWidget);
      expect(find.text('EVENTO'), findsOneWidget);

      // Verificar datos de Tarea: prioridad Alta, fecha, estado Pendiente
      expect(find.text('Prioridad Alta'), findsOneWidget);
      expect(find.text('17 oct 2026'), findsOneWidget);
      expect(find.text('Pendiente'), findsNWidgets(2)); // Tarea y Recordatorio

      // Verificar datos de Evento: estado Completado
      expect(find.text('Completado'), findsOneWidget);
    });

    testWidgets('NUNCA muestra texto del tipo "null" en la pantalla', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Ningún widget de texto debe contener el literal 'null'
      expect(find.text('null'), findsNothing);
      expect(find.textContaining('null', findRichText: true), findsNothing);
    });

    testWidgets('Permite eliminar un elemento de la lista', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Cumpleaños de Ana'), findsOneWidget);

      // Tocar el botón eliminar del segundo elemento
      final deleteButtons = find.byTooltip('Eliminar');
      expect(deleteButtons, findsNWidgets(3));
      await tester.tap(deleteButtons.at(1));
      await tester.pump();

      // Cumpleaños de Ana debe desaparecer y mostrar snackbar con Deshacer
      expect(find.text('Cumpleaños de Ana'), findsNothing);
      expect(find.text('Deshacer'), findsOneWidget);
    });

    testWidgets('Permite editar el título de un elemento', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Abrir diálogo de edición del primer elemento
      final editButtons = find.byTooltip('Editar');
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Editar elemento'), findsOneWidget);

      // Modificar el texto del título
      final titleField = find.widgetWithText(TextField, 'Entregar el proyecto');
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, 'Entregar proyecto de IA modificado');

      // Guardar cambios en el diálogo
      final saveChangesBtn = find.widgetWithText(ElevatedButton, 'Guardar cambios');
      await tester.tap(saveChangesBtn);
      await tester.pumpAndSettle();

      // Verificar que se actualizó en la pantalla
      expect(find.text('Entregar proyecto de IA modificado'), findsOneWidget);
    });

    testWidgets('Permite filtrar elementos por tipo usando los chips', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Filtrar solo Tareas
      await tester.tap(find.text('Tareas (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Entregar el proyecto'), findsOneWidget);
      expect(find.text('Cumpleaños de Ana'), findsNothing);
      expect(find.text('Clase de natación'), findsNothing);

      // Filtrar solo Eventos
      await tester.tap(find.text('Eventos (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Clase de natación'), findsOneWidget);
      expect(find.text('Entregar el proyecto'), findsNothing);
    });

    testWidgets('Botón de guardar elementos confirmados envía los datos al backend', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final saveButton = find.text('Guardar elementos confirmados (3)');
      expect(saveButton, findsOneWidget);

      await tester.tap(saveButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(mockClient.saveCalled, isTrue);
      expect(mockClient.savedItemsCount, 3);
      expect(find.text('Elementos guardados'), findsOneWidget);
      expect(find.text('Se han guardado 3 elementos correctamente en tu bitácora.'), findsOneWidget);
    });
  });
}
