import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sgsc_ejecutiva/widgets/executive_charts.dart';
import 'package:sgsc_ejecutiva/core/theme.dart';

import 'widget_test.dart' as helpers;

Future<void> choose(WidgetTester tester, String mode) async {
  await tester.ensureVisible(find.widgetWithText(ChoiceChip, mode));
  await tester.tap(find.widgetWithText(ChoiceChip, mode));
  await tester.pumpAndSettle();
}

void main() {
  final rows = List.generate(
    7,
    (i) => {'id': i + 1, 'nombre': 'Categoría ${i + 1}', 'total': 7 - i},
  );
  Widget chart({
    List<dynamic>? data,
    num total = 28,
    ValueChanged<String>? onSelect,
    double width = 320,
    double scale = 1,
  }) => MaterialApp(
    theme: executiveTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: CategoryPieChart(
                rows: data ?? rows,
                total: total,
                onSelect: onSelect ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'Views preserve counts, percentages, Others and filter callbacks',
    (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(chart(onSelect: selected.add));
      for (final mode in ['Barras', 'Treemap', 'Composición', 'Dona']) {
        await choose(tester, mode);
        await tester.pumpAndSettle();
        expect(selected, isEmpty);
        expect(find.text('7 · 25.0%'), findsOneWidget);
        expect(find.text('3 · 10.7%'), findsOneWidget);
        expect(find.text('Otros'), findsNothing);
        expect(find.textContaining('Fuera de la gráfica: 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Categoría 1'));
      expect(selected, ['1']);
      await tester.ensureVisible(find.text('Ver todos (7)'));
      await tester.tap(find.text('Ver todos (7)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Categoría 7'));
      await tester.tap(find.text('Categoría 7'));
      expect(selected, ['1', '7']);
    },
  );

  testWidgets('Empty and zero data have no misleading chart', (tester) async {
    for (final data in [
      <dynamic>[],
      [
        {'id': null, 'nombre': 'Sin información', 'total': 0},
      ],
    ]) {
      await tester.pumpWidget(chart(data: data, total: 0));
      expect(find.text('Sin datos para mostrar.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Stack requires matching denominator and updates retain view', (
    tester,
  ) async {
    await tester.pumpWidget(chart());
    await choose(tester, 'Composición');
    await tester.pumpAndSettle();
    await tester.pumpWidget(chart(total: 40));
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Composición'))
          .onSelected,
      isNull,
    );
    expect(find.text('7 · 17.5%'), findsOneWidget);
    await choose(tester, 'Barras');
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      chart(
        data: [
          {'id': null, 'nombre': 'Sin información', 'total': 40},
        ],
        total: 40,
      ),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Barras'))
          .selected,
      true,
    );
    expect(find.text('40 · 100.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selector supports keyboard and narrow layouts with large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    for (final width in [280.0, 440.0]) {
      await tester.pumpWidget(chart(width: width, scale: 2));
      for (final mode in ['Barras', 'Treemap', 'Composición', 'Dona']) {
        await choose(tester, mode);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(chart());
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Barras'))
          .selected,
      true,
    );
    semantics.dispose();
  });
  testWidgets('Visual samples for the three chart views', (tester) async {
    await helpers.prepare(tester);
    await tester.pumpWidget(helpers.wrap(chart()));
    await tester.pumpAndSettle();
    for (final mode in ['Dona', 'Barras', 'Composición', 'Treemap']) {
      if (mode != 'Dona') await choose(tester, mode);
      await tester.pumpAndSettle();
      await helpers.screenshot(tester, 'categorias-$mode');
    }
  });
}
