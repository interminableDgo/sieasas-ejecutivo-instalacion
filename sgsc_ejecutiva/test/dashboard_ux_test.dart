import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/main.dart';
import 'package:sgsc_ejecutiva/screens/dashboard/dashboard_screen.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/widgets/executive_charts.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

const user = {
  'nombres': 'Cuenta',
  'apellidos': 'Ejecutiva',
  'correo': 'prueba@example.com',
  'entidad': 'Nuevo León',
};
final municipios = [
  'Monterrey',
  'Guadalupe',
  'Apodaca',
  'San Nicolás de los Garza',
  'General Escobedo',
  'Santa Catarina',
  'Juárez',
  'García',
  'San Pedro Garza García',
  'Cadereyta Jiménez',
  'Linares',
  'Montemorelos',
];
List<Map<String, Object>> rowsOf(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    {'id': i + 1, 'nombre': names[i], 'total': 40 - i},
];
final catalogs = {
  'municipios': rowsOf(municipios),
  'apoyos': rowsOf(['Medicamento', 'Traslado', 'Estudio']),
  'dependencias': rowsOf(['Secretaría de Salud', 'DIF']),
  'grupos': rowsOf(['Adultos mayores', 'Infancias']),
  'estatus': rowsOf(['Recibida', 'Resuelta']),
};
final summary = {
  'total': 400,
  'activas': 250,
  'resueltas': 150,
  'municipios': rowsOf(municipios),
  'apoyos': catalogs['apoyos'],
  'grupos': catalogs['grupos'],
  'dependencias': catalogs['dependencias'],
  'regiones': [],
  'tendencia': List.generate(
    12,
    (i) => {
      'mes': '2026-${(i + 1).toString().padLeft(2, '0')}',
      'recibidas': i + 2,
      'resueltas': i % 4,
    },
  ),
};

class Backend {
  final requests = <Uri>[];
  Completer<void>? gate;
  bool failDashboard = false;
  bool emptyDashboard = false;
  late final api = ExecutiveApi(
    client: MockClient((request) async {
      requests.add(request.url);
      final path = request.url.path;
      if (path == '/ejecutivo/dashboard' && gate != null) await gate!.future;
      if (path == '/ejecutivo/dashboard' && failDashboard) {
        return http.Response(jsonEncode({'detail': 'Error de consulta'}), 503);
      }
      if (path.startsWith('/ejecutivo/exportar')) {
        return http.Response(
          jsonEncode({'detail': 'El servidor no pudo generar el archivo.'}),
          500,
        );
      }
      final values = request.url.queryParametersAll.entries
          .where((e) => e.key.endsWith('_id'))
          .fold(0, (n, e) => n + e.value.length);
      final data = switch (path) {
        '/auth/login' => {'token': 't', 'requires_2fa': false, 'user': user},
        '/ejecutivo/catalogos' => catalogs,
        '/ejecutivo/solicitudes' => {
          'items': [],
          'total': values == 0 ? 400 : 7 * values,
        },
        '/ejecutivo/dashboard' =>
          emptyDashboard
              ? {
                  ...summary,
                  'total': 0,
                  'activas': 0,
                  'resueltas': 0,
                  'municipios': [],
                }
              : summary,
        '/ejecutivo/comparacion' => {
          'periodos': [
            for (final (i, start)
                in request.url.queryParametersAll['inicio']!.indexed)
              {
                'inicio': start,
                'total': 3 + i,
                'activas': 2,
                'resueltas': 1 + i,
                'variacion': i == 0
                    ? null
                    : {
                        for (final k in ['total', 'activas', 'resueltas'])
                          k: {'diferencia': 1, 'porcentaje': 10},
                      },
              },
          ],
        },
        _ => <String, Object>{},
      };
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  int count(String path) => requests.where((u) => u.path == path).length;
}

/// Adds one month of the current year to the comparison.
Future<void> choose(WidgetTester tester, String month) async {
  await reveal(tester, find.text('Elegir meses'));
  await tester.tap(find.text('Elegir meses'));
  await settle(tester);
  await tester.tap(find.text(month));
  await tester.pumpAndSettle();
  final compare = find.textContaining(RegExp(r'^Comparar \d+ periodos$'));
  await tester.ensureVisible(compare);
  await tester.pumpAndSettle();
  await tester.tap(compare);
  await settle(tester);
}

Future<void> fonts(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final loader = FontLoader('Mulish')
    ..addFont(rootBundle.load('assets/fonts/Mulish.ttf'));
  await tester.runAsync(() => loader.load());
}

Future<Backend> open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Map<String, String> account = user,
}) async {
  await fonts(tester, size);
  final backend = Backend();
  await tester.pumpWidget(
    MaterialApp(
      theme: executiveTheme(),
      home: Scaffold(
        body: DashboardScreen(api: backend.api, user: account, onLogout: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

ScrollPosition position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.textContaining('Filtros'));
  await settle(tester);
}

Finder fieldOf(String label) =>
    find.bySemanticsLabel(RegExp('^$label: .*Elegir opciones'));

/// Opens a filter's option list, optionally searches, and ticks [names].
Future<void> tick(
  WidgetTester tester,
  String label,
  List<String> names, {
  String? search,
  bool close = true,
}) async {
  await tester.tap(fieldOf(label));
  await settle(tester);
  if (search != null) {
    await tester.enterText(find.byType(TextField).last, search);
    await tester.pumpAndSettle();
  }
  for (final name in names) {
    final option = find.widgetWithText(CheckboxListTile, name);
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }
  if (close) {
    await tester.tap(find.textContaining(RegExp(r'^Listo')));
    await settle(tester);
  }
}

/// Scrolls [target] to the middle of its list: clear of the pinned bar at
/// the top and of the export bar at the bottom.
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.runAsync(
    () =>
        Scrollable.ensureVisible(tester.element(target.first), alignment: 0.5),
  );
  await tester.pumpAndSettle();
}

Finder applyButton() => find.textContaining(RegExp(r'^Ver \d+ solicitud'));

/// The comparison now sits under the trend, at the end of «Resumen».
Future<void> openComparison(WidgetTester tester) async {
  final toggle = find.text('Comparar meses o años');
  await tester.scrollUntilVisible(
    toggle,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await reveal(tester, toggle);
  await tester.tap(toggle);
  await settle(tester);
}

/// The map is the second view of the municipalities card.
Future<void> showMap(WidgetTester tester) async {
  final views = find.byKey(const ValueKey('municipality-view'));
  await tester.scrollUntilVisible(
    views,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await reveal(tester, views);
  await tester.tap(find.descendant(of: views, matching: find.text('Mapa')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selecting a bar keeps the scroll position and the content', (
    tester,
  ) async {
    final backend = await open(tester);
    await tester.scrollUntilVisible(
      find.text('Solicitudes por municipio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();
    final before = position(tester).pixels;
    expect(before, greaterThan(300));
    // What the person sees: an unselected bar must not move on screen.
    final anchor = find.text('Guadalupe');
    final seen = tester.getTopLeft(anchor).dy;
    expect(find.text('Apodaca').hitTestable(), findsOneWidget);

    backend.gate = Completer();
    await tester.tap(find.text('Apodaca').hitTestable().first);
    await tester.pump();
    await tester.pump();
    // While loading: content stays mounted and a discreet status is shown.
    expect(find.text('Solicitudes por municipio'), findsOneWidget);
    expect(find.text('Actualizando…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(tester.getTopLeft(anchor).dy, moreOrLessEquals(seen, epsilon: 1));
    backend.gate!.complete();
    backend.gate = null;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, moreOrLessEquals(seen, epsilon: 1));
    expect(find.text('Actualizando…'), findsNothing);
    expect(find.text('Municipio: Apodaca'), findsOneWidget);
  });

  testWidgets('multi-select with search; batch apply with result count', (
    tester,
  ) async {
    final backend = await open(tester);
    await openFilters(tester);
    expect(find.text('Filtrar solicitudes'), findsOneWidget);
    expect(find.text('Ver 400 solicitudes'), findsOneWidget);
    expect(find.textContaining('Fechas de registro'), findsNothing);

    backend.requests.clear();
    await tick(tester, 'Municipio', ['Linares'], search: 'lina', close: false);
    // Searching again keeps what was ticked and "Todos" is no longer active.
    await tester.enterText(find.byType(TextField).last, 'nicolas');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'San Nicolás de los Garza'),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 seleccionadas'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pumpAndSettle();
    final todos = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Todos'),
    );
    expect(todos.value, isFalse);
    await tester.tap(find.text('Listo (2)'));
    await settle(tester);

    expect(find.text('2 seleccionados'), findsOneWidget);
    expect(find.text('Ver 14 solicitudes'), findsOneWidget);
    expect(backend.count('/ejecutivo/dashboard'), 1);
    expect(
      backend.requests
          .lastWhere((u) => u.path == '/ejecutivo/dashboard')
          .queryParameters
          .containsKey('municipio_id'),
      isFalse,
      reason: 'counts per municipality ignore the municipality filter',
    );
    expect(find.text('Municipio: Linares'), findsNothing);
    final counted = backend.requests.lastWhere(
      (u) => u.path == '/ejecutivo/solicitudes',
    );
    expect(counted.queryParametersAll['municipio_id'], ['11', '4']);

    await tester.tap(applyButton());
    await tester.pumpAndSettle();
    expect(find.text('Municipio: Linares'), findsOneWidget);
    expect(find.text('Municipio: San Nicolás de los Garza'), findsOneWidget);
    expect(backend.count('/ejecutivo/dashboard'), 2);

    // Reopening shows what is applied.
    await openFilters(tester);
    expect(find.text('2 seleccionados'), findsOneWidget);
  });

  testWidgets('Resumen opens first; requests live in their own tab', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Solicitudes (400)'), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-card')), findsOneWidget);
    expect(find.text('Detalle de solicitudes'), findsNothing);
    // The answer to "which municipality has more" is in the summary itself.
    await tester.scrollUntilVisible(
      find.text('Solicitudes por municipio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Monterrey'), findsWidgets);
    await tester.tap(find.text('Solicitudes (400)'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle de solicitudes'), findsOneWidget);
    expect(find.text('Solicitudes por municipio'), findsNothing);
    expect(find.byKey(const ValueKey('panel-tabs')), findsOneWidget);
  });

  testWidgets('total says what it counts; each part has its status colour', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.textContaining('400 solicitudes totales', findRichText: true),
      findsOneWidget,
    );
    final breakdown = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('summary-breakdown')),
        matching: find.byType(RichText),
      ),
    );
    expect(
      breakdown.text.toPlainText(),
      '250 activas (incluye pendientes) · 150 resueltas',
    );
    final numbers = <String, Color?>{};
    breakdown.text.visitChildren((span) {
      if (span is TextSpan && RegExp(r'^\d+$').hasMatch(span.text ?? '')) {
        numbers[span.text!] = span.style?.color;
      }
      return true;
    });
    expect(numbers['250'], statusTextColor(StatusKind.pending));
    expect(numbers['150'], statusGreen);
  });

  testWidgets('municipality filter shows counts, most requests first', (
    tester,
  ) async {
    await open(tester);
    await openFilters(tester);
    await tester.tap(fieldOf('Municipio'));
    await settle(tester);
    expect(find.byKey(const ValueKey('option-order')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-1')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('count-1'))).data,
      '40',
    );
    final first = tester
        .getTopLeft(find.widgetWithText(CheckboxListTile, 'Monterrey'))
        .dy;
    final second = tester
        .getTopLeft(find.widgetWithText(CheckboxListTile, 'Guadalupe'))
        .dy;
    expect(first, lessThan(second), reason: '40 before 39');
  });

  testWidgets('"Todos" clears the specific selections of a filter', (
    tester,
  ) async {
    await open(tester);
    await openFilters(tester);
    await tick(tester, 'Municipio', ['Monterrey', 'Guadalupe'], close: false);
    expect(find.text('2 seleccionadas'), findsOneWidget);
    // Back to the top of the option list, where «Todos» is.
    await tester.scrollUntilVisible(
      find.widgetWithText(CheckboxListTile, 'Todos'),
      -100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Todos'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sin selección: se incluyen todas las opciones.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Listo'));
    await settle(tester);
    expect(find.text('Ver 400 solicitudes'), findsOneWidget);
  });

  testWidgets('a single selection can be removed inside the sheet', (
    tester,
  ) async {
    await open(tester);
    await openFilters(tester);
    await tick(tester, 'Tipo de apoyo', ['Medicamento', 'Estudio']);
    await tester.tap(find.byTooltip('Quitar Medicamento'));
    await settle(tester);
    expect(find.byTooltip('Quitar Medicamento'), findsNothing);
    expect(find.byTooltip('Quitar Estudio'), findsOneWidget);
  });

  testWidgets('"Limpiar todo" asks before clearing', (tester) async {
    await open(tester);
    await openFilters(tester);
    await tick(tester, 'Estatus', ['Recibida']);
    await tester.tap(find.text('Limpiar todo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Quitar todos los filtros?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quitar Recibida'), findsOneWidget);
    await tester.tap(find.text('Limpiar todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar todos'));
    await settle(tester);
    expect(find.byTooltip('Quitar Recibida'), findsNothing);
  });

  testWidgets('closing with pending changes asks before discarding', (
    tester,
  ) async {
    await open(tester);
    await openFilters(tester);
    await tick(tester, 'Municipio', ['Linares'], search: 'linares');
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar cambios?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Filtrar solicitudes'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Filtrar solicitudes'), findsNothing);
    expect(find.textContaining('Municipio: '), findsNothing);
  });

  testWidgets('Escape closes the option list', (tester) async {
    await open(tester);
    await openFilters(tester);
    await tester.tap(fieldOf('Municipio'));
    await settle(tester);
    expect(find.byType(CheckboxListTile), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Filtrar solicitudes'), findsOneWidget);
  });

  testWidgets('applied chips wrap and "Ver todos" reveals the rest', (
    tester,
  ) async {
    await open(tester);
    await openFilters(tester);
    await tick(tester, 'Municipio', [
      'Monterrey',
      'Guadalupe',
      'Apodaca',
      'Juárez',
    ]);
    await tester.tap(applyButton());
    await tester.pumpAndSettle();
    expect(find.text('Filtros (4)'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(3));
    expect(find.text('Ver todos (4)'), findsOneWidget);
    expect(find.byType(ListView), findsNothing, reason: 'no horizontal list');
    await tester.tap(find.text('Ver todos (4)'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNWidgets(4));
    for (final chip in tester.widgetList<InputChip>(find.byType(InputChip))) {
      final box = tester.getRect(find.byWidget(chip));
      expect(box.right, lessThanOrEqualTo(390));
      expect(box.left, greaterThanOrEqualTo(0));
    }
  });

  testWidgets('removing a filter can be undone', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(
      find.text('Solicitudes por municipio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guadalupe').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Municipio: Guadalupe'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(InputChip), matching: find.byType(Icon)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Municipio: Guadalupe'), findsNothing);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(find.text('Municipio: Guadalupe'), findsOneWidget);
  });

  testWidgets('bars accept several values and keep active rows visible', (
    tester,
  ) async {
    await open(tester);
    await openFilters(tester);
    await tick(tester, 'Municipio', ['Linares', 'Montemorelos'], search: 'l');
    await tester.tap(applyButton());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Solicitudes por municipio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('Solicitudes por municipio'),
      matching: find.byType(Container),
    );
    Finder inCard(String text) =>
        find.descendant(of: card.first, matching: find.text(text));
    expect(inCard('Monterrey'), findsOneWidget);
    expect(inCard('Santa Catarina'), findsNothing);
    expect(inCard('Linares'), findsOneWidget);
    expect(inCard('Montemorelos'), findsOneWidget);
  });

  testWidgets('hiding the comparison keeps periods and needs no request', (
    tester,
  ) async {
    final backend = await open(tester);
    await openComparison(tester);
    await choose(tester, 'Marzo');
    await choose(tester, 'Enero');
    final analyzed = find.textContaining(RegExp(r'^Marzo \d{4}$'));
    final reference = find.textContaining(RegExp(r'^Enero \d{4}$'));
    expect(analyzed, findsWidgets);
    expect(reference, findsWidgets);
    final requests = backend.count('/ejecutivo/comparacion');

    await reveal(tester, find.text('Ocultar comparación'));
    await tester.tap(find.text('Ocultar comparación'));
    await settle(tester);
    expect(find.text('Comparar periodos'), findsNothing);
    await openComparison(tester);
    expect(analyzed, findsWidgets);
    expect(reference, findsWidgets);
    expect(backend.count('/ejecutivo/comparacion'), requests);
  });

  testWidgets('export: summary of applied filters, format, failures in place', (
    tester,
  ) async {
    final backend = await open(tester);
    await openFilters(tester);
    await tick(tester, 'Tipo de apoyo', ['Traslado', 'Estudio']);
    await tester.tap(applyButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar reporte'));
    await settle(tester);
    expect(find.text('•  Tipo de apoyo: Traslado, Estudio'), findsOneWidget);
    expect(
      find.textContaining('Periodo de registro: Todo el historial'),
      findsOneWidget,
    );
    expect(find.textContaining('Fechas'), findsNothing);
    expect(find.text('Descargar Excel'), findsOneWidget);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar PDF'));
    await tester.pumpAndSettle();
    final sent = backend.requests.lastWhere(
      (u) => u.path == '/ejecutivo/exportar/pdf',
    );
    expect(sent.queryParametersAll['tipo_apoyo_id'], ['2', '3']);
    expect(
      find.textContaining('El servidor no pudo generar el archivo.'),
      findsOneWidget,
    );
    expect(find.text('Descargar PDF'), findsOneWidget);
  });

  // iPhone SE / 13 / 15 and common Android sizes (small, Galaxy, Pixel).
  for (final size in const [
    Size(375, 667),
    Size(390, 844),
    Size(393, 852),
    Size(360, 640),
    Size(360, 800),
    Size(412, 915),
  ]) {
    testWidgets(
      'sheets fit the phone at ${size.width}x${size.height}',
      variant: TargetPlatformVariant.mobile(),
      (tester) async {
        await open(tester, size: size);
        void fits(Finder sheet) {
          final r = tester.getRect(sheet.first);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(size.width));
          expect(r.top, greaterThanOrEqualTo(0));
          expect(r.bottom, lessThanOrEqualTo(size.height));
        }

        await openFilters(tester);
        fits(find.byType(BottomSheet));
        expect(
          tester.getSize(find.text('Limpiar todo')).height,
          lessThan(24),
          reason: 'one line, not wrapped',
        );
        expect(applyButton(), findsOneWidget);
        expect(
          tester.getRect(applyButton()).bottom,
          lessThanOrEqualTo(size.height),
        );
        await tester.tap(fieldOf('Municipio'));
        await settle(tester);
        fits(find.byType(BottomSheet).last);
        expect(
          tester.getSize(find.byType(BottomSheet).last).height,
          lessThanOrEqualTo(size.height * 0.75 + 1),
        );
        await tester.tap(find.text('Listo'));
        await settle(tester);
        await tester.tap(find.byTooltip('Cerrar'));
        await settle(tester);
        await tester.tap(find.text('Exportar reporte'));
        await settle(tester);
        fits(find.byType(BottomSheet));
        expect(
          tester.getRect(find.text('Descargar Excel')).bottom,
          lessThanOrEqualTo(size.height),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a wide browser window still behaves like a phone', (
    tester,
  ) async {
    await fonts(tester, const Size(1280, 800));
    final backend = Backend();
    await tester.pumpWidget(SgscApp(api: backend.api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Una contraseña de prueba',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    await openFilters(tester);
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.width, lessThanOrEqualTo(phoneMaxWidth));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('switching Meses/Años keeps the chosen periods', (tester) async {
    await open(tester);
    await openComparison(tester);
    await choose(tester, 'Marzo');
    final march = find.textContaining(RegExp(r'^Marzo \d{4}$'));
    expect(march, findsWidgets);
    final year = RegExp(r'\d{4}')
        .firstMatch(tester.widget<Text>(march.first).data!)![0]!;

    await reveal(tester, find.text('Años'));
    await tester.tap(find.text('Años'));
    await settle(tester);
    expect(find.text(year), findsWidgets);
    expect(march, findsNothing);
    await reveal(tester, find.text('Meses'));
    await tester.tap(find.text('Meses'));
    await settle(tester);
    expect(march, findsWidgets, reason: 'the month comes back');
  });

  testWidgets('Android back returns from a sub-view to the panel', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Mi perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Mi perfil'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Mi perfil'), findsNothing);
    expect(find.byKey(const ValueKey('panel-tabs')), findsOneWidget);
  });

  testWidgets(
    'larger system text (130%) does not break sheets',
    variant: TargetPlatformVariant.mobile(),
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: const Size(360, 640));
      await openFilters(tester);
      await tester.tap(fieldOf('Municipio'));
      await settle(tester);
      await tester.tap(find.textContaining(RegExp(r'^Listo')));
      await settle(tester);
      await tester.tap(find.byTooltip('Cerrar'));
      await settle(tester);
      await tester.tap(find.text('Exportar reporte'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checkboxes use the brand orange on both platforms',
    variant: TargetPlatformVariant.mobile(),
    (tester) async {
      await open(tester);
      await openFilters(tester);
      await tick(tester, 'Municipio', ['Monterrey'], close: false);
      for (final tile in tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      )) {
        expect(tile.activeColor, brand);
      }
    },
  );

  group('municipality map', () {
    const nl = {...user, 'clave_inegi': '19'};
    setUp(() {
      // Link the test catalog to INEGI keys: Monterrey is 19039.
      final list = catalogs['municipios']!;
      list[0] = {...list[0], 'clave_inegi': '19039'};
    });

    Future<Offset> municipality(WidgetTester tester, String code) async {
      final json = jsonDecode(
        await tester.runAsync(
              () => rootBundle.loadString('assets/nl-municipios.json'),
            ) ??
            '{}',
      ) as Map<String, dynamic>;
      final shape = (json['municipios'] as List).firstWhere(
        (m) => m['cvegeo'] == code,
      );
      final path = parseSvgPathData(shape['path'] as String);
      final center = path.getBounds().center;
      expect(path.contains(center), isTrue);
      final rect = tester.getRect(
        find.byKey(const ValueKey('municipality-map')),
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('municipality-map')),
                  )
                  .painter
              as dynamic;
      final view = painter.view as Rect;
      return rect.topLeft + (center - view.topLeft) * (rect.width / view.width);
    }

    testWidgets('is the second view of the municipalities card', (
      tester,
    ) async {
      final backend = await open(tester, account: nl);
      // The ranked list answers "which has more" first; the map is optional.
      expect(find.byType(MunicipalityMap), findsNothing);
      await showMap(tester);
      expect(find.byType(MunicipalityMap), findsOneWidget);
      expect(find.text('Solicitudes por municipio'), findsOneWidget);
      await tester.ensureVisible(find.byType(MunicipalityMap));
      await tester.pumpAndSettle();
      final painted = find.byKey(const ValueKey('municipality-map'));
      final before = tester.getTopLeft(painted.first);
      final fullView =
          (tester.widget<CustomPaint>(painted).painter as dynamic).view as Rect;
      expect(find.text('Toca un municipio'), findsOneWidget);
      await tester.tapAt(await municipality(tester, '19039'));
      await tester.pumpAndSettle();
      expect(find.text('Monterrey'), findsWidgets);
      expect(find.textContaining('40 solicitudes'), findsOneWidget);
      expect(
        tester.getTopLeft(painted.first),
        before,
        reason: 'the map must not shift under the finger',
      );

      expect(find.byTooltip('Ver todo el estado'), findsOneWidget);
      final zoomView =
          (tester.widget<CustomPaint>(painted).painter as dynamic).view as Rect;
      expect(zoomView.width, lessThan(fullView.width));
      for (final path in ['/ejecutivo/dashboard', '/ejecutivo/solicitudes']) {
        expect(
          backend.requests
              .lastWhere((u) => u.path == path)
              .queryParameters['municipio_id'],
          '1',
        );
      }
      await tester.tapAt(await municipality(tester, '19039'));
      await tester.pumpAndSettle();
      expect(find.text('Quitar municipio'), findsNothing);
      expect(
        (tester.widget<CustomPaint>(painted).painter as dynamic).view,
        fullView,
      );
      expect(
        backend.requests
            .lastWhere((u) => u.path == '/ejecutivo/dashboard')
            .queryParameters
            .containsKey('municipio_id'),
        isFalse,
      );
    });

    testWidgets(
      'map replaces municipality, preserves other filters and clears during loading',
      (tester) async {
        catalogs['municipios']![1] = {
          ...catalogs['municipios']![1],
          'clave_inegi': '19026',
        };
        final backend = await open(tester, account: nl);
        await openFilters(tester);
        await tick(tester, 'Tipo de apoyo', ['Medicamento']);
        await tester.tap(applyButton());
        await settle(tester);
        await showMap(tester);
        await tester.ensureVisible(find.byType(MunicipalityMap));
        await tester.pumpAndSettle();
        await tester.tapAt(await municipality(tester, '19039'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Ver todo el estado'));
        await tester.pumpAndSettle();
        await tester.tapAt(await municipality(tester, '19026'));
        await tester.pumpAndSettle();
        var query = backend.requests
            .lastWhere((u) => u.path == '/ejecutivo/dashboard')
            .queryParametersAll;
        expect(query['municipio_id'], ['2']);
        expect(query['tipo_apoyo_id'], ['1']);
        backend.gate = Completer<void>();
        await tester.tap(find.text('Quitar municipio'));
        await tester.pump();
        expect(find.text('Actualizando solicitudes...'), findsOneWidget);
        query = backend.requests
            .lastWhere((u) => u.path == '/ejecutivo/solicitudes')
            .queryParametersAll;
        expect(query.containsKey('municipio_id'), isFalse);
        expect(query['tipo_apoyo_id'], ['1']);
        expect(query['page'], ['0']);
        backend.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Toca un municipio'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'map keeps selection on error, retries and displays filtered empty state',
      (tester) async {
        final backend = await open(tester, account: nl);
        await showMap(tester);
        await tester.ensureVisible(find.byType(MunicipalityMap));
        await tester.pumpAndSettle();
        backend.failDashboard = true;
        await tester.tapAt(await municipality(tester, '19039'));
        await tester.pumpAndSettle();
        expect(
          find.text('No se pudieron actualizar los datos.'),
          findsOneWidget,
        );
        expect(
          tester.widget<MunicipalityMap>(find.byType(MunicipalityMap)).active,
          {'1'},
        );
        backend.failDashboard = false;
        backend.emptyDashboard = true;
        await tester.ensureVisible(find.byTooltip('Reintentar mapa'));
        await tester.tap(find.byTooltip('Reintentar mapa'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(MunicipalityMap));
        await tester.pumpAndSettle();
        expect(
          find.text('Sin solicitudes con los filtros actuales.'),
          findsOneWidget,
        );
        expect(find.text('Quitar municipio'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('is not shown for other states', (tester) async {
      await open(tester, account: {...user, 'clave_inegi': '05'});
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.byType(MunicipalityMap), findsNothing);
    });
  });
}
