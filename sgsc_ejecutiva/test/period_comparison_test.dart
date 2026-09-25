import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/widgets/period_comparison.dart';

import 'widget_test.dart' show prepare, wrap, screenshot;

void main() {
  testWidgets(
    'Mobile comparison updates automatically and selects months in a sheet',
    (tester) async {
      await prepare(tester);
      tester.view.physicalSize = const Size(390, 844);
      Map<String, String>? query;
      final api = ExecutiveApi(
        client: MockClient((request) async {
          query = request.url.queryParameters;
          return http.Response(
            jsonEncode({
              'a': {'total': 15, 'activas': 6, 'resueltas': 6},
              'b': {'total': 19, 'activas': 7, 'resueltas': 8},
              'variacion': {
                'total': {'diferencia': 4, 'porcentaje': 26.7},
                'activas': {'diferencia': 1, 'porcentaje': 16.7},
                'resueltas': {'diferencia': 2, 'porcentaje': 33.3},
              },
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
      expect(query!['municipio_id'], '3');
      expect(query!.containsKey('fecha_inicio'), false);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Solicitudes registradas'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'comparacion-mobile');
      final original = query!['b_inicio'];
      await tester.tap(find.text('Periodo a analizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Febrero'));
      await tester.pumpAndSettle();
      await screenshot(tester, 'comparacion-selector');
      await tester.tap(find.textContaining('Usar Febrero'));
      await tester.pumpAndSettle();
      expect(query!['b_inicio']!.endsWith('-02-01'), true);
      expect(query!['b_fin'], endsWith('-02-28'));
      expect(query!['b_inicio'], isNot(original));
      await tester.tap(find.text('Años'));
      await tester.pumpAndSettle();
      expect(query!['a_inicio']!.endsWith('-01-01'), true);
      expect(query!['b_fin']!.endsWith('-12-31'), true);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Periodo a analizar'));
      await tester.pumpAndSettle();
      expect(find.byType(YearPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
