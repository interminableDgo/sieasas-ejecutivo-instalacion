import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/main.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/screens/dashboard/dashboard_screen.dart';
import 'package:sgsc_ejecutiva/screens/solicitudes/nueva_solicitud_screen.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

const user = {
  'nombres': 'Cuenta',
  'apellidos': 'Ejecutiva',
  'correo': 'prueba@example.com',
  'entidad': 'Nuevo León',
  'clave_inegi': '19',
};
const catalogs = {
  'municipios': [
    {'id': 1, 'nombre': 'Monterrey'},
  ],
  'apoyos': [
    {'id': 1, 'nombre': 'Medicamento'},
  ],
  'dependencias': [
    {'id': 1, 'nombre': 'Secretaría de Salud'},
  ],
  'regiones': [
    {'id': 1, 'nombre': 'Metropolitana'},
  ],
  'grupos': [],
  'estatus': [],
};
Map<String, dynamic> emptySummary = {
  'total': 0,
  'activas': 0,
  'resueltas': 0,
  'municipios': [],
  'apoyos': [],
  'dependencias': [],
  'grupos': [],
  'regiones': [],
  'tendencia': [],
};
ExecutiveApi mockApi({bool fail = false, bool populated = false}) =>
    ExecutiveApi(
      client: MockClient((request) async {
        if (fail && request.url.path == '/ejecutivo/dashboard') {
          return http.Response(
            jsonEncode({'detail': 'No se pudo consultar la base de datos.'}),
            503,
          );
        }
        Object data;
        switch (request.url.path) {
          case '/auth/login':
            data = {'token': 'test-token', 'requires_2fa': false, 'user': user};
          case '/ejecutivo/catalogos':
            data = catalogs;
          case '/ejecutivo/solicitudes':
            data = {'items': [], 'total': 0};
          case '/ejecutivo/dashboard':
            data = populated
                ? {
                    ...emptySummary,
                    'total': 36,
                    'activas': 24,
                    'resueltas': 12,
                    'tendencia': List.generate(
                      12,
                      (i) => {
                        'mes': '2026-${(i + 1).toString().padLeft(2, '0')}',
                        'recibidas': i + 2,
                        'resueltas': i % 4,
                      },
                    ),
                    'municipios': [
                      {'id': 1, 'nombre': 'Monterrey', 'total': 36},
                    ],
                    'regiones': [
                      {'id': 1, 'nombre': 'Metropolitana', 'total': 36},
                    ],
                  }
                : emptySummary;
          default:
            data = {'message': 'Operación completada.'};
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

Future<void> prepare(WidgetTester tester) async {
  tester.view.physicalSize = const Size(440, 920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final loader = FontLoader('Mulish')
    ..addFont(rootBundle.load('assets/fonts/Mulish.ttf'));
  await tester.runAsync(() => loader.load());
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await tester.runAsync(() => icons.load());
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['SCREENSHOT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
  image!.dispose();
}

Widget wrap(Widget child) =>
    RepaintBoundary(key: const ValueKey('capture'), child: child);
Widget dashboard(ExecutiveApi api) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: executiveTheme(),
  home: Scaffold(
    body: DashboardScreen(api: api, user: user, onLogout: () {}),
  ),
);

void main() {
  testWidgets('Login validates and opens the real empty state', (tester) async {
    await prepare(tester);
    await tester.pumpWidget(wrap(SgscApp(api: mockApi())));
    await tester.pumpAndSettle();
    await screenshot(tester, '01-acceso');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
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
    expect(find.text('Aún no hay solicitudes'), findsOneWidget);
    expect(find.text('Registrar primera solicitud'), findsOneWidget);
    final export = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Exportar reporte'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(export.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await screenshot(tester, '02-panel-vacio');
  });
  testWidgets('Eye button inside the field shows and hides the password', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(wrap(SgscApp(api: mockApi())));
    await tester.pumpAndSettle();
    EditableText field() =>
        tester.widget<EditableText>(find.byType(EditableText).at(1));
    expect(find.text('Mostrar contraseña'), findsNothing);
    expect(field().obscureText, true);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pumpAndSettle();
    expect(field().obscureText, false);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pumpAndSettle();
    expect(field().obscureText, true);
    await screenshot(tester, '01-acceso-ojo');
  });
  testWidgets('Connection failure does not masquerade as empty results', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(wrap(dashboard(mockApi(fail: true))));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Aún no hay solicitudes'), findsNothing);
    await screenshot(tester, '03-error-conexion');
  });
  testWidgets('Filtered empty state can clear filters', (tester) async {
    await prepare(tester);
    await tester.pumpWidget(wrap(dashboard(mockApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtros'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Municipio: .*Elegir opciones')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Monterrey'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listo (1)'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ver 0 solicitudes'));
    await tester.pumpAndSettle();
    expect(find.text('Sin resultados'), findsOneWidget);
    await screenshot(tester, '04-sin-resultados');
    await tester.ensureVisible(find.text('Limpiar filtros'));
    await tester.tap(find.text('Limpiar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay solicitudes'), findsOneWidget);
  });
  testWidgets('Missing required SSNL catalogs disable continuing', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: executiveTheme(),
        home: Scaffold(
          body: NewRequestScreen(
            api: mockApi(),
            catalogs: const {},
            entity: 'Nuevo León',
            onBack: () {},
            onSaved: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continuar'));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Copied image keeps the title and data but not the controls', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: executiveTheme(),
        home: const Scaffold(
          body: ExecutiveCard(
            title: 'Apoyos solicitados',
            source: 'Fuente',
            copyable: true,
            child: Column(
              children: [
                CopyExclude(child: Text('Dona · Barras')),
                Text('Cirugía 29'),
                CopyExclude(child: Text('Ver todos (26)')),
              ],
            ),
          ),
        ),
      ),
    );
    final state = tester.state<State<ExecutiveCard>>(
      find.byType(ExecutiveCard),
    );
    late Future<Object?> pending;
    await tester.runAsync(() async {
      pending = (state as dynamic).image() as Future<Object?>;
    });
    await tester.pump();
    expect(find.text('Apoyos solicitados'), findsOneWidget);
    expect(find.text('Cirugía 29'), findsOneWidget);
    expect(find.text('Dona · Barras'), findsNothing);
    expect(find.text('Ver todos (26)'), findsNothing);
    expect(find.byTooltip('Copiar imagen de la gráfica'), findsNothing);
    expect(find.byTooltip('Cómo se calcula'), findsNothing);
    final png = await tester.runAsync(() => pending) as List<int>;
    // PNG signature
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    await tester.pump();
    expect(find.text('Dona · Barras'), findsOneWidget);
    expect(find.text('Ver todos (26)'), findsOneWidget);
    expect(find.byTooltip('Copiar imagen de la gráfica'), findsOneWidget);
  });
  testWidgets('Populated dashboard draws the charts', (tester) async {
    await prepare(tester);
    await tester.pumpWidget(wrap(dashboard(mockApi(populated: true))));
    await tester.pumpAndSettle();
    expect(find.text('36'), findsWidgets);
    expect(find.byTooltip('Copiar imagen de la gráfica'), findsWidgets);
    await screenshot(tester, '05-panel-con-datos-prueba');
    await tester.scrollUntilVisible(
      find.text('Solicitudes por municipio'),
      300,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await screenshot(tester, '06-municipios');
  });
}
