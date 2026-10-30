import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

import 'widget_test.dart'
    show prepare, wrap, screenshot, dashboard, catalogs, emptySummary;

void main() {
  testWidgets('Table sits under the totals and its search autocompletes', (
    tester,
  ) async {
    await prepare(tester);
    final requests = <Uri>[];
    final row = {
      'solicitud_id': 9,
      'folio': 'Solicitud #9',
      'fecha_registro': '2026-10-20T10:00:00',
      'municipio': 'Monterrey',
      'tipo_apoyo': 'Medicamento',
      'dependencia': 'Secretaría de Salud',
      'estatus': 'Recibido',
      'beneficiario': 'José Pérez',
      'solicitante': 'Ana Núñez',
    };
    final api = ExecutiveApi(
      client: MockClient((request) async {
        requests.add(request.url);
        final q = request.url.queryParameters['q'];
        final Object data = switch (request.url.path) {
          '/ejecutivo/catalogos' => catalogs,
          '/ejecutivo/dashboard' => {
            ...emptySummary,
            'total': 1,
            'activas': 1,
            'municipios': [
              {'id': 1, 'nombre': 'Monterrey', 'total': 1},
            ],
          },
          '/ejecutivo/solicitudes/sugerencias' => {
            'items': [
              {'texto': 'José Pérez', 'tipo': 'Beneficiario'},
            ],
          },
          '/ejecutivo/solicitudes' =>
            q == 'sin coincidencias'
                ? {'items': [], 'total': 0}
                : {
                    'items': [row],
                    'total': 1,
                  },
          _ => {},
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

    // Order: total of requests, then the table.
    final totals = tester
        .getTopLeft(find.text('Solicitudes registradas').first)
        .dy;
    final table = tester.getTopLeft(find.text('Detalle de solicitudes')).dy;
    expect(totals < table, isTrue);
    // The charts come after it (still below the visible area).
    expect(find.text('Solicitudes por mes de registro'), findsNothing);
    expect(find.text('José Pérez'), findsOneWidget);
    expect(find.text('Ana Núñez'), findsOneWidget);
    expect(find.text('20/10/2026'), findsOneWidget);

    final field = find.descendant(
      of: find.byKey(const ValueKey('requests-table-card')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'jose');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final suggestion = find.widgetWithText(ListTile, 'José Pérez');
    expect(suggestion, findsOneWidget);
    expect(
      requests.last.path,
      anyOf('/ejecutivo/solicitudes/sugerencias', '/ejecutivo/solicitudes'),
    );
    await screenshot(tester, 'busqueda-sugerencias');
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    final searched = requests.lastWhere(
      (u) => u.path == '/ejecutivo/solicitudes',
    );
    expect(searched.queryParameters['q'], 'José Pérez');
    expect(searched.queryParameters['page'], '0');
    expect(find.text('1 resultado para «José Pérez»'), findsOneWidget);

    await tester.enterText(field, 'sin coincidencias');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay solicitudes que coincidan con «sin coincidencias».'),
      findsOneWidget,
    );
    // The search narrows only the table; the charts keep their data.
    expect(find.byType(ExecutiveCard), findsWidgets);
    expect(requests.where((u) => u.path == '/ejecutivo/dashboard').length, 1);

    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(
      requests
          .lastWhere((u) => u.path == '/ejecutivo/solicitudes')
          .queryParameters
          .containsKey('q'),
      isFalse,
    );
    expect(find.text('José Pérez'), findsOneWidget);
  });
}
