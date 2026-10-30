import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/main.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/widgets/executive_charts.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

import 'widget_test.dart'
    show prepare, wrap, screenshot, dashboard, catalogs, emptySummary;

void main() {
  testWidgets('HU3 historical trend renders and selects a single month', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(
      wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: executiveTheme(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('HU3 · Enero de 2020 · Datos de prueba'),
                  TrendChart(
                    points: [
                      {'mes': '2020-01', 'recibidas': 2, 'resueltas': 1},
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = find.descendant(
      of: find.byType(TrendChart),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(chart);
    await tester.pumpAndSettle();
    expect(
      find.text('2020-01 · 2 registradas · 1 resueltas actualmente'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'HU3-tendencia-historica-corregida');
  });

  testWidgets('HU1 recovery validates email and displays generic response', (
    tester,
  ) async {
    await prepare(tester);
    final requests = <http.Request>[];
    const message =
        'Si el correo está asociado a una cuenta autorizada, recibirás instrucciones para recuperar el acceso.';
    final api = ExecutiveApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'message': message}),
          202,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(wrap(SgscApp(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(requests, isEmpty);
    await screenshot(tester, 'HU1-correo-invalido');
    await tester.enterText(find.byType(TextFormField), 'prueba@example.com');
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/auth/forgot-password');
    expect(jsonDecode(requests.single.body), {'correo': 'prueba@example.com'});
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    await screenshot(tester, 'HU1-recuperacion-respuesta');
    expect(tester.takeException(), isNull);
  });

  testWidgets('HU4 category filters list and detail returns to same context', (
    tester,
  ) async {
    await prepare(tester);
    final requests = <Uri>[];
    final row = {
      'solicitud_id': 9,
      'folio': 'Solicitud #9',
      'municipio': 'Monterrey',
      'tipo_apoyo': 'Medicamento',
      'dependencia': 'Secretaría de Salud',
      'estatus': 'Inicio',
    };
    final api = ExecutiveApi(
      client: MockClient((request) async {
        requests.add(request.url);
        final data = switch (request.url.path) {
          '/ejecutivo/catalogos' => catalogs,
          '/ejecutivo/dashboard' => {
            ...emptySummary,
            'total': 1,
            'activas': 1,
            'municipios': [
              {'id': 1, 'nombre': 'Monterrey', 'total': 1},
            ],
          },
          '/ejecutivo/solicitudes' => {
            'total': 1,
            'items': [row],
          },
          '/ejecutivo/solicitudes/9' => {
            ...row,
            'nombres': 'Persona',
            'apellidos': 'Ficticia',
            'descripcion': 'Solicitud ficticia para prueba del sprint 1',
          },
          _ => <String, dynamic>{},
        };
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(wrap(dashboard(api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Solicitudes por municipio'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    // The bar of the chart, not the Municipio column of the table above.
    final bar = find.descendant(
      of: find.ancestor(
        of: find.text('Solicitudes por municipio'),
        matching: find.byType(ExecutiveCard),
      ),
      matching: find.text('Monterrey'),
    );
    await tester.ensureVisible(bar);
    // Move it out from under the pinned filter bar before tapping.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle();
    await tester.tap(bar);
    await tester.pumpAndSettle();
    for (final path in ['/ejecutivo/dashboard', '/ejecutivo/solicitudes']) {
      expect(
        requests
            .lastWhere((r) => r.path == path)
            .queryParameters['municipio_id'],
        '1',
      );
    }
    await tester.scrollUntilVisible(
      find.text('Solicitud #9'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    // Out from under the pinned filter bar.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle();
    await screenshot(tester, 'HU4-listado-filtrado');
    await tester.tap(find.text('Solicitud #9'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle de solicitud'), findsOneWidget);
    expect(find.text('Persona Ficticia'), findsOneWidget);
    expect(requests.last.path, '/ejecutivo/solicitudes/9');
    await screenshot(tester, 'HU4-detalle');
    await tester.tap(find.byTooltip('Volver').first);
    await tester.pumpAndSettle();
    expect(find.text('Municipio: Monterrey'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
