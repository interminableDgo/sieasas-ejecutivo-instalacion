import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sgsc_ejecutiva/widgets/export_sheet.dart';
import 'package:sgsc_ejecutiva/widgets/filter_sheet.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/main.dart';

import 'dashboard_ux_test.dart' show Backend;
import 'widget_test.dart' show prepare, wrap, screenshot;

void main() {
  testWidgets('HU6 dates reach dashboard list and export and survive retry', (
    tester,
  ) async {
    await prepare(tester);
    final backend = Backend();
    await tester.pumpWidget(wrap(SgscApp(api: backend.api)));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'prueba@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Una contraseña de prueba',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Filtros'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Todo el historial'));
    await tester.tap(find.text('Todo el historial'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    // Date fields of the period editor, not the search box of the table.
    final periodFields = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText != 'Buscar solicitud',
    );
    await tester.enterText(periodFields.at(0), '01/02/2024');
    await tester.enterText(periodFields.at(1), '29/02/2024');
    await tester.tap(find.text('Aplicar periodo'));
    await tester.pumpAndSettle();
    expect(find.text('2024-02-01 al 2024-02-29'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Ver 400 solicitudes'));
    await tester.pumpAndSettle();
    for (final path in ['/ejecutivo/dashboard', '/ejecutivo/solicitudes']) {
      final uri = backend.requests.lastWhere((u) => u.path == path);
      expect(uri.queryParameters['fecha_inicio'], '2024-02-01');
      expect(uri.queryParameters['fecha_fin'], '2024-02-29');
    }
    final requestCount = backend.requests.length;
    await tester.scrollUntilVisible(
      find.text('Apoyos solicitados'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    // Centred, so the chip is clear of the pinned bar and the export bar.
    await Scrollable.ensureVisible(
      tester.element(find.widgetWithText(ChoiceChip, 'Barras').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Barras').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Clasificación por grupo vulnerable'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    // Centred, so the chip is clear of the pinned bar and the export bar.
    await Scrollable.ensureVisible(
      tester.element(find.widgetWithText(ChoiceChip, 'Treemap').last),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Treemap').last);
    await tester.pumpAndSettle();
    expect(backend.requests.length, requestCount);
    await tester.tap(find.byKey(const ValueKey('export-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2024-02-01 al 2024-02-29'), findsOneWidget);
    expect(
      find.textContaining('Sin nombres ni registros individuales'),
      findsOneWidget,
    );
    await screenshot(tester, 'HU6-exportacion-filtros-datos-sinteticos');
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    for (var retry = 0; retry < 2; retry++) {
      await tester.tap(find.text('Descargar PDF'));
      await tester.pumpAndSettle();
      final uri = backend.requests.lastWhere(
        (u) => u.path == '/ejecutivo/exportar/pdf',
      );
      expect(uri.queryParameters['fecha_inicio'], '2024-02-01');
      expect(uri.queryParameters['fecha_fin'], '2024-02-29');
      expect(uri.queryParameters['chart_apoyos'], 'bars');
      expect(uri.queryParameters['chart_grupos'], 'treemap');
      expect(
        find.textContaining('El servidor no pudo generar el archivo.'),
        findsOneWidget,
      );
    }
    await screenshot(tester, 'HU6-error-reintento-datos-sinteticos');
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(360, 640), const Size(1440, 900)]) {
    testWidgets('HU6 export busy and success at $size', (tester) async {
      await prepare(tester);
      tester.view.physicalSize = size;
      final gate = Completer<String?>();
      String? selected;
      await tester.pumpWidget(
        wrap(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: executiveTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      selected = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        constraints: const BoxConstraints(maxWidth: 440),
                        builder: (_) => SizedBox(
                          height: 540,
                          child: ExportSheet(
                            total: 20,
                            appliedFilters: const [
                              'Periodo de registro: 2024-02-01 al 2024-02-29',
                              'Municipio: Prueba A, Prueba B',
                            ],
                            onExport: (_) => gate.future,
                          ),
                        ),
                      );
                    },
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await screenshot(
        tester,
        'HU6-exportacion-${size.width.toInt()}-datos-sinteticos',
      );
      await tester.tap(find.text('Descargar Excel'));
      await tester.pump();
      expect(find.text('Generando Excel…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Generando Excel…'),
            )
            .onPressed,
        isNull,
      );
      gate.complete(null);
      await tester.pumpAndSettle();
      expect(selected, 'xlsx');
      expect(find.byType(ExportSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  test('HU6 open periods', () {
    expect(
      periodSummary({
        'fecha_inicio': ['2024-01-01'],
      }),
      '2024-01-01 al Sin límite final',
    );
    expect(
      periodSummary({
        'fecha_fin': ['2024-01-31'],
      }),
      'Sin límite inicial al 2024-01-31',
    );
  });
}
