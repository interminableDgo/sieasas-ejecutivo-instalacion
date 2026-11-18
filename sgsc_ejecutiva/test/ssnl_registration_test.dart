import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/core/curp_validator.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/screens/solicitudes/nueva_solicitud_screen.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

import 'widget_test.dart' show prepare, wrap, screenshot;

void main() {
  test('CURP validates structure, actual dates and checksum', () {
    expect(validateCurp(''), isNull);
    expect(validateCurp('GODE561231HDFRRN00'), isNull);
    expect(validateCurp('gode561231hdfrrn00'), isNull);
    expect(validateCurp('G1'), contains('iniciales'));
    expect(validateCurp('GODE'), contains('18 caracteres'));
    expect(validateCurp('GODE560231'), contains('no existe'));
    expect(validateCurp('GODE561231X'), contains('sexo'));
    expect(validateCurp('GODE561231HXX'), contains('entidad'));
    expect(validateCurp('GODE561231HDFA'), contains('consonantes'));
    expect(validateCurp('GODE561231HDFRRN01'), contains('verificador'));
    expect(
      validateCurp('GODE990101HDFRRNA0', today: DateTime(2026)),
      contains('futura'),
    );
    expect(validateCurp('GODE000229HDFRRN00'), contains('no existe'));
  });

  testWidgets('CURP errors update while typing without submitting', (
    tester,
  ) async {
    await prepare(tester);
    final api = ExecutiveApi(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      wrap(
        MaterialApp(
          theme: executiveTheme(),
          home: Scaffold(
            body: NewRequestScreen(
              api: api,
              catalogs: const {
                'generos': [
                  {'id': 1, 'nombre': 'Hombre'},
                ],
                'entidades': [
                  {'id': 1, 'nombre': 'Nuevo León'},
                ],
              },
              entity: 'Nuevo León',
              onBack: () {},
              onSaved: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final curp = find.descendant(
      of: find.ancestor(
        of: find.text('CURP (opcional)'),
        matching: find.byType(LabeledField),
      ),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(curp);
    await tester.enterText(curp, 'GODE');
    await tester.pumpAndSettle();
    expect(find.textContaining('18 caracteres (llevas 4)'), findsOneWidget);
    await tester.enterText(curp, 'GODE561231X');
    await tester.pumpAndSettle();
    expect(find.textContaining('El sexo en la CURP'), findsOneWidget);
    expect(find.textContaining('18 caracteres (llevas'), findsNothing);
    await tester.enterText(curp, 'GODE561231HDFRRN01');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El dígito verificador de la CURP'),
      findsOneWidget,
    );
    await tester.enterText(curp, 'GODE561231HDFRRN00');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El dígito verificador de la CURP'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SSNL wizard selects existing people and submits original request fields',
    (tester) async {
      await prepare(tester);
      tester.view.physicalSize = const Size(390, 844);
      Map<String, dynamic>? posted;
      String? saved;
      final api = ExecutiveApi(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posted = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({'solicitud_id': 9, 'folio': 'Solicitud #9'}),
              201,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': r.url.queryParameters['tipo'] == 'beneficiario'
                      ? 21
                      : 22,
                  'nombre': 'Expediente de prueba',
                },
              ],
            }),
            200,
          );
        }),
      );
      final cats = <String, dynamic>{
        for (final key in [
          'municipios',
          'generos',
          'entidades',
          'seguridad_social',
          'grupos',
          'parentescos',
          'apoyos',
          'origenes',
          'canales',
          'unidades',
        ])
          key: [
            {'id': 1, 'nombre': 'Opción $key'},
          ],
      };
      await tester.pumpWidget(
        wrap(
          MaterialApp(
            theme: executiveTheme(),
            home: Scaffold(
              body: NewRequestScreen(
                api: api,
                catalogs: cats,
                entity: 'Nuevo León',
                onBack: () {},
                onSaved: (v) => saved = v,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, '07-registro-SSNL');
      for (final person in ['beneficiario', 'solicitante']) {
        await tester.tap(find.text('Usar $person existente'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Buscar $person'));
        await tester.tap(find.text('Buscar $person'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Expediente de prueba').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continuar'));
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
      }
      Future<void> choose(String label, String key) async {
        final field = find.ancestor(
          of: find.text(label),
          matching: find.byType(LabeledField),
        );
        final dropdown = find.descendant(
          of: field,
          matching: find.byType(DropdownButtonFormField<int>),
        );
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Opción $key').last);
        await tester.pumpAndSettle();
      }

      await choose('Tipo de apoyo', 'apoyos');
      await choose('Origen de la solicitud', 'origenes');
      await choose('Canal de recepción', 'canales');
      await choose('Unidad tratante', 'unidades');
      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      final description = find.descendant(
        of: find.ancestor(
          of: find.text('Descripción de la solicitud'),
          matching: find.byType(LabeledField),
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Completa este campo.'), findsOneWidget);
      expect(posted, isNull);
      await screenshot(tester, 'HU5-descripcion-obligatoria');
      await tester.ensureVisible(description);
      await tester.enterText(description, 'Solicitud de prueba');
      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Solicitud de prueba'), findsOneWidget);
      expect(posted, isNull);
      await tester.ensureVisible(find.text('Paso anterior'));
      await tester.tap(find.text('Paso anterior'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(description).controller!.text,
        'Solicitud de prueba',
      );
      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registrar solicitud'));
      await screenshot(tester, 'HU5-confirmacion-solicitud');
      await tester.tap(find.text('Registrar solicitud'));
      await tester.pumpAndSettle();
      expect(saved, 'Solicitud #9');
      expect(posted!['beneficiario_id'], 21);
      expect(posted!['solicitante_id'], 22);
      expect(posted!['canal_id'], 1);
      expect(posted!['descripcion'], 'Solicitud de prueba');
      expect(posted!['idempotencia'], isNotEmpty);
      expect(posted!.containsKey('prioridad_id'), false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Step indicator, colony catalog with derived postal code and same address',
    (tester) async {
      await prepare(tester);
      Map<String, dynamic>? posted;
      final api = ExecutiveApi(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posted = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({'solicitud_id': 9, 'folio': 'Solicitud #9'}),
              201,
            );
          }
          if (r.url.path.endsWith('/colonias')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 5, 'nombre': 'Obispado', 'codigo_postal': '64060'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {'id': 21, 'nombre': 'Expediente de prueba'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final cats = <String, dynamic>{
        for (final key in [
          'municipios',
          'generos',
          'entidades',
          'parentescos',
          'apoyos',
          'origenes',
          'canales',
          'unidades',
        ])
          key: [
            {'id': 1, 'nombre': 'Opción $key'},
          ],
      };
      await tester.pumpWidget(
        wrap(
          MaterialApp(
            theme: executiveTheme(),
            home: Scaffold(
              body: NewRequestScreen(
                api: api,
                catalogs: cats,
                entity: 'Nuevo León',
                onBack: () {},
                onSaved: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StepProgress), findsOneWidget);
      expect(find.text('PASO 1 DE 8 · BENEFICIARIO'), findsOneWidget);
      expect(find.text('Datos personales'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Paso 1 de 8: Beneficiario, Datos personales'),
        findsOneWidget,
      );
      await screenshot(tester, 'paso-visible');

      Future<void> tapText(String text) async {
        await tester.ensureVisible(find.text(text).last);
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      Future<void> choose(String label, String option) async {
        final dropdown = find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(LabeledField),
          ),
          matching: find.byType(DropdownButtonFormField<int>),
        );
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last);
        await tester.pumpAndSettle();
      }

      Future<void> type(String label, String value) async {
        final field = find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(LabeledField),
          ),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }

      // Beneficiario existente: se omiten sus pasos de domicilio e información social.
      await tapText('Usar beneficiario existente');
      await tapText('Buscar beneficiario');
      await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
      await tester.pumpAndSettle();
      await tapText('Expediente de prueba');
      await tapText('Continuar');
      expect(find.text('PASO 2 DE 6 · SOLICITANTE'), findsOneWidget);

      await type('Nombre(s)', 'Ana');
      await type('Apellidos', 'Prueba');
      await choose('Parentesco con el beneficiario', 'Opción parentescos');
      expect(find.text('Especifica el parentesco'), findsNothing);
      final birth = find.descendant(
        of: find.ancestor(
          of: find.text('Fecha de nacimiento'),
          matching: find.byType(LabeledField),
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(birth);
      await tester.tap(birth);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();
      await tapText('Continuar');

      // Domicilio propio: colonia del catálogo y código postal derivado.
      expect(find.text('Se asigna al elegir la colonia'), findsOneWidget);
      expect(find.text('Código postal'), findsOneWidget);
      await choose(
        'Municipio de domicilio · Nuevo León',
        'Opción municipios',
      );
      await choose('Colonia', 'Obispado · CP 64060');
      expect(find.text('64060'), findsOneWidget);
      await screenshot(tester, 'colonia-catalogo');

      // Mismo domicilio: la ubicación no se vuelve a capturar.
      await tapText('Vive en el mismo domicilio que el beneficiario');
      expect(find.text('Colonia'), findsNothing);
      expect(find.text('Calle'), findsNothing);
      await type('Teléfono', '8112345678');
      await tapText('Continuar');
      await choose('Tipo de apoyo', 'Opción apoyos');
      await choose('Origen de la solicitud', 'Opción origenes');
      await choose('Canal de recepción', 'Opción canales');
      await choose('Unidad tratante', 'Opción unidades');
      await tapText('Continuar');
      await type('Descripción de la solicitud', 'Solicitud de prueba');
      await tapText('Continuar');
      expect(find.text('El mismo del beneficiario'), findsOneWidget);
      await tapText('Registrar solicitud');
      final applicant = posted!['solicitante'] as Map<String, dynamic>;
      expect(applicant['mismo_domicilio'], true);
      for (final key in [
        'calle',
        'numero',
        'colonia_id',
        'municipio_id',
        'codigo_postal',
        'colonia',
        'otro_parentesco',
      ]) {
        expect(applicant.containsKey(key), false, reason: key);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
