import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/screens/solicitudes/nueva_solicitud_screen.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

import 'widget_test.dart' show prepare, wrap, screenshot;

void main() {
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
      await tester.tap(find.text('Registrar solicitud'));
      await tester.pumpAndSettle();
      expect(saved, 'Solicitud #9');
      expect(posted!['beneficiario_id'], 21);
      expect(posted!['solicitante_id'], 22);
      expect(posted!['canal_id'], 1);
      expect(posted!.containsKey('prioridad_id'), false);
      expect(tester.takeException(), isNull);
    },
  );
}
