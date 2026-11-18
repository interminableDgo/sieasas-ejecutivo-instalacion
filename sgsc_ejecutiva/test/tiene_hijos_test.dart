import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';
import 'package:sgsc_ejecutiva/services/executive_api.dart';
import 'package:sgsc_ejecutiva/screens/solicitudes/nueva_solicitud_screen.dart';
import 'package:sgsc_ejecutiva/widgets/executive_widgets.dart';

import 'widget_test.dart' show prepare, wrap;

/// Claves que el formulario enviaba para un beneficiario nuevo antes de la
/// pregunta «¿Tiene hijos?»; el contrato con el backend no cambia.
const beneficiaryKeys = {
  'nombres',
  'apellidos',
  'curp',
  'fecha_nacimiento',
  'genero_id',
  'municipio_nacimiento_id',
  'municipio_id',
  'colonia_id',
  'calle',
  'numero',
  'tiempo_residencia',
  'con_quien_vive_id',
  'numero_hijos',
  'hijo_seguridad_social',
  'estudia',
  'ocupacion_id',
  'fuente_ingresos_id',
  'seguridad_social_id',
  'afiliacion',
  'grupo_vulnerable_id',
  'tramita_personalmente',
  'migrante',
  'codigo2024',
};

class _Form {
  _Form(this.tester);
  final WidgetTester tester;
  Map<String, dynamic>? posted;

  Future<void> open() async {
    await prepare(tester);
    tester.view.physicalSize = const Size(390, 844);
    final api = ExecutiveApi(
      client: MockClient((r) async {
        if (r.method == 'POST') {
          posted = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'solicitud_id': 9, 'folio': 'Solicitud #9'}),
            201,
          );
        }
        final items = switch (r.url.path) {
          '/ejecutivo/colonias' => [
            {'id': 5, 'nombre': 'Obispado', 'codigo_postal': '64060'},
          ],
          '/ejecutivo/municipios-nacimiento' => [
            {'id': 7, 'nombre': 'Monterrey'},
          ],
          _ => [
            {'id': 22, 'nombre': 'Expediente de prueba'},
          ],
        };
        return http.Response(jsonEncode({'items': items}), 200);
      }),
    );
    addTearDown(api.dispose);
    final cats = <String, dynamic>{
      for (final key in [
        'municipios',
        'generos',
        'entidades',
        'con_quien_vive',
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
              onSaved: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(LabeledField),
    ),
    matching: find.byType(TextFormField),
  );

  Future<void> tapText(String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> type(String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
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

  /// Beneficiario nuevo: datos personales y domicilio hasta «Información social».
  Future<void> toSocialStep() async {
    await type('Nombre(s)', 'Ana');
    await type('Apellidos', 'Prueba');
    final birth = field('Fecha de nacimiento');
    await tester.ensureVisible(birth);
    await tester.tap(birth);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    await choose('Género', 'Opción generos');
    await choose('Estado de nacimiento', 'Opción entidades');
    await choose('Municipio de nacimiento', 'Monterrey');
    await tapText('Continuar');
    await choose('Municipio de domicilio · Nuevo León', 'Opción municipios');
    await choose('Colonia', 'Obispado · CP 64060');
    await type('Calle', 'Calle de prueba');
    await type('Número exterior / interior', '1');
    await type('Años de residencia', '2');
    await tapText('Continuar');
    expect(find.text('Información social'), findsWidgets);
    await choose('¿Con quién vive?', 'Opción con_quien_vive');
    await choose('Seguridad social', 'Opción seguridad_social');
    await choose('Grupo vulnerable', 'Opción grupos');
  }

  bool get onSocialStep =>
      find.text('PASO 3 DE 8 · BENEFICIARIO').evaluate().isNotEmpty;

  /// Del paso social al envío, con un solicitante existente.
  Future<Map<String, dynamic>> submitFromSocialStep() async {
    await tapText('Continuar');
    expect(onSocialStep, isFalse);
    await tapText('Usar solicitante existente');
    await tapText('Buscar solicitante');
    await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
    await tester.pumpAndSettle();
    await tapText('Expediente de prueba');
    await tapText('Continuar');
    await choose('Tipo de apoyo', 'Opción apoyos');
    await choose('Origen de la solicitud', 'Opción origenes');
    await choose('Canal de recepción', 'Opción canales');
    await choose('Unidad tratante', 'Opción unidades');
    await tapText('Continuar');
    await type('Descripción de la solicitud', 'Solicitud de prueba');
    await tapText('Continuar');
    await tapText('Registrar solicitud');
    expect(posted, isNotNull);
    return posted!['beneficiario'] as Map<String, dynamic>;
  }
}

void main() {
  testWidgets('sin respuesta no avanza y no muestra la cantidad', (
    tester,
  ) async {
    final form = _Form(tester);
    await form.open();
    await form.toSocialStep();
    expect(find.text('¿Tiene hijos?'), findsOneWidget);
    expect(find.text('¿Cuántos hijos tiene?'), findsNothing);
    expect(find.text('Algún hijo tiene seguridad social'), findsNothing);
    await form.tapText('Continuar');
    expect(find.text('Indica si tiene hijos.'), findsOneWidget);
    expect(form.onSocialStep, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'No envía 0 hijos, sin seguridad social y con el contrato original',
    (tester) async {
      final form = _Form(tester);
      await form.open();
      await form.toSocialStep();
      await form.tapText('No');
      expect(find.text('¿Cuántos hijos tiene?'), findsNothing);
      expect(find.text('Algún hijo tiene seguridad social'), findsNothing);
      final b = await form.submitFromSocialStep();
      expect(b['numero_hijos'], 0);
      expect(b['hijo_seguridad_social'], false);
      expect(b.containsKey('tiene_hijos'), isFalse);
      expect(form.posted!.containsKey('tiene_hijos'), isFalse);
      expect(beneficiaryKeys.containsAll(b.keys), isTrue, reason: '${b.keys}');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Sí exige un entero entre 1 y 100', (tester) async {
    final form = _Form(tester);
    await form.open();
    await form.toSocialStep();
    await form.tapText('Sí');
    expect(find.text('¿Cuántos hijos tiene?'), findsOneWidget);
    expect(find.text('Algún hijo tiene seguridad social'), findsOneWidget);
    await form.tapText('Continuar');
    expect(find.text('Completa este campo.'), findsOneWidget);
    expect(form.onSocialStep, isTrue);
    for (final invalid in ['0', '101', '1.5', 'dos', '-1']) {
      await form.type('¿Cuántos hijos tiene?', invalid);
      await form.tapText('Continuar');
      expect(
        find.text('Ingresa un número entero entre 1 y 100.'),
        findsOneWidget,
        reason: invalid,
      );
      expect(form.onSocialStep, isTrue, reason: invalid);
    }
    for (final valid in ['1', '100']) {
      await form.type('¿Cuántos hijos tiene?', valid);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FormField<String>>(form.field('¿Cuántos hijos tiene?'))
            .validator!(valid),
        isNull,
        reason: valid,
      );
    }
    await form.type('¿Cuántos hijos tiene?', '2');
    final b = await form.submitFromSocialStep();
    expect(b['numero_hijos'], 2);
    expect(b.containsKey('tiene_hijos'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sí → No limpia y fija 0; No → Sí vuelve a pedir la cantidad', (
    tester,
  ) async {
    final form = _Form(tester);
    await form.open();
    await form.toSocialStep();
    await form.tapText('Sí');
    await form.type('¿Cuántos hijos tiene?', '3');
    await form.tapText('Algún hijo tiene seguridad social');
    await form.tapText('No');
    expect(find.text('¿Cuántos hijos tiene?'), findsNothing);
    await form.tapText('Sí');
    final count = tester.widget<TextFormField>(
      form.field('¿Cuántos hijos tiene?'),
    );
    expect(count.controller!.text, isEmpty);
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isFalse,
    );
    await form.tapText('Continuar');
    expect(find.text('Completa este campo.'), findsOneWidget);
    await form.tapText('No');
    final b = await form.submitFromSocialStep();
    expect(b['numero_hijos'], 0);
    expect(b['hijo_seguridad_social'], false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la respuesta se conserva al regresar y aparece en la revisión', (
    tester,
  ) async {
    final form = _Form(tester);
    await form.open();
    await form.toSocialStep();
    await form.tapText('Sí');
    await form.type('¿Cuántos hijos tiene?', '4');
    await form.tapText('Continuar');
    await form.tapText('Paso anterior');
    expect(form.onSocialStep, isTrue);
    expect(
      tester
          .widget<TextFormField>(form.field('¿Cuántos hijos tiene?'))
          .controller!
          .text,
      '4',
    );
    await form.tapText('Continuar');
    await form.tapText('Usar solicitante existente');
    await form.tapText('Buscar solicitante');
    await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
    await tester.pumpAndSettle();
    await form.tapText('Expediente de prueba');
    await form.tapText('Continuar');
    await form.choose('Tipo de apoyo', 'Opción apoyos');
    await form.choose('Origen de la solicitud', 'Opción origenes');
    await form.choose('Canal de recepción', 'Opción canales');
    await form.choose('Unidad tratante', 'Opción unidades');
    await form.tapText('Continuar');
    await form.type('Descripción de la solicitud', 'Solicitud de prueba');
    await form.tapText('Continuar');
    expect(find.text('¿Tiene hijos?'), findsOneWidget);
    expect(find.text('¿Cuántos hijos tiene?'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(form.posted, isNull);
    expect(tester.takeException(), isNull);
  });
}
