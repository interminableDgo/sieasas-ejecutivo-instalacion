import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/widgets/executive_charts.dart';
import 'package:sgsc_ejecutiva/widgets/period_comparison.dart';

import 'widget_test.dart' show prepare, wrap, screenshot;

/// Scrolls the control into view first: the chart may have moved it away.
Future<void> press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
}

void main() {
  testWidgets(
    'Compares several months, shows months without records and picks in a sheet',
    (tester) async {
      await prepare(tester);
      tester.view.physicalSize = const Size(390, 844);
      Map<String, List<String>>? query;
      final api = ExecutiveApi(
        client: MockClient((request) async {
          query = request.url.queryParametersAll;
          final starts = query!['inicio']!;
          // The second period has no records.
          final totals = [
            for (var i = 0; i < starts.length; i++) i == 1 ? 0 : 10 + i,
          ];
          return http.Response(
            jsonEncode({
              'periodos': [
                for (var i = 0; i < starts.length; i++)
                  {
                    'inicio': starts[i],
                    'fin': query!['fin']![i],
                    'total': totals[i],
                    'activas': totals[i] ~/ 2,
                    'resueltas': totals[i] - totals[i] ~/ 2,
                    'variacion': i == 0
                        ? null
                        : {
                            for (final k in ['total', 'activas', 'resueltas'])
                              k: {
                                'diferencia': totals[i] - totals[i - 1],
                                'porcentaje': totals[i - 1] == 0
                                    ? null
                                    : -100.0,
                              },
                          },
                  },
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        wrap(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: executiveTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PeriodComparison(
                    api: api,
                    filters: const {
                      'municipio_id': ['3'],
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Three complete months by default, in one request with the filters.
      expect(query!['municipio_id'], ['3']);
      expect(query!.containsKey('fecha_inicio'), false);
      expect(query!['inicio'], hasLength(3));
      expect(find.text('Periodos a comparar (3 de 12)'), findsOneWidget);
      expect(find.byType(PeriodColumnsChart), findsOneWidget);
      expect(find.text('Sin solicitudes registradas'), findsOneWidget);
      expect(
        find.text('1 de 3 periodos sin registros; se muestran en 0.'),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'comparacion-mobile');
      await tester.ensureVisible(find.byType(PeriodColumnsChart));
      await tester.pumpAndSettle();
      await screenshot(tester, 'comparacion-grafica');

      // A fourth month from the sheet.
      await press(tester, find.text('Elegir meses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Febrero'));
      await tester.pumpAndSettle();
      await screenshot(tester, 'comparacion-selector');
      await tester.tap(find.text('Comparar 4 periodos'));
      await tester.pumpAndSettle();
      expect(query!['inicio'], hasLength(4));
      expect(query!['inicio']!.any((d) => d.endsWith('-02-01')), true);
      expect(query!['fin']!.any((d) => d.endsWith('-02-28')), true);
      // Sent from the oldest to the most recent.
      expect([...query!['inicio']!]..sort(), query!['inicio']);

      // Shortcuts and removing a period.
      await press(tester, find.text('Últimos 6 meses'));
      await tester.pumpAndSettle();
      expect(query!['inicio'], hasLength(6));
      await press(
        tester,
        find
            .byWidgetPredicate(
              (w) => w is Tooltip && (w.message ?? '').startsWith('Quitar '),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(query!['inicio'], hasLength(5));

      // The indicator switch changes what the columns show.
      await press(tester, find.text('Resueltas'));
      await tester.pumpAndSettle();
      expect(find.text('Solicitudes resueltas por periodo'), findsOneWidget);

      await press(tester, find.text('Años'));
      await tester.pumpAndSettle();
      expect(query!['inicio'], hasLength(3));
      expect(query!['inicio']!.every((d) => d.endsWith('-01-01')), true);
      expect(query!['fin']!.every((d) => d.endsWith('-12-31')), true);
      await press(tester, find.text('Meses'));
      await tester.pumpAndSettle();
      expect(query!['inicio'], hasLength(5), reason: 'the months come back');
      expect(tester.takeException(), isNull);

      // Twelve periods on a narrow phone with large text.
      await press(tester, find.text('Últimos 12 meses'));
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(query!['inicio'], hasLength(12));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(PeriodColumnsChart));
      await tester.pumpAndSettle();
      await screenshot(tester, 'comparacion-12-meses');
      await press(tester, find.text('Elegir meses'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Llegaste al máximo de periodos. Quita uno para elegir otro.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
