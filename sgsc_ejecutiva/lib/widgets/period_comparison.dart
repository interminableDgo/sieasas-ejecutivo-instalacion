import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/executive_api.dart';
import 'executive_widgets.dart';
import 'executive_charts.dart';
import 'filter_sheet.dart';

/// What the person chose to compare, plus the last result and the query it
/// answers. Owned by the dashboard so hiding the comparison (which disposes
/// the widget) keeps the periods, and showing it again needs no request when
/// nothing changed. Months and years are kept apart, so switching Meses/Años
/// brings back what was chosen in each.
class ComparisonSelection {
  static const maxPeriods = 12;
  bool annual = false;
  late List<DateTime> months, years;
  Map<String, dynamic>? result;
  String? resultKey;
  ComparisonSelection() {
    final now = DateTime.now();
    // The last three complete months and the last three years.
    months = [for (var i = 3; i >= 1; i--) DateTime(now.year, now.month - i)];
    years = [for (var i = 2; i >= 0; i--) DateTime(now.year - i)];
  }
  List<DateTime> get periods => annual ? years : months;
  set periods(List<DateTime> value) {
    final sorted = [...value]..sort();
    if (annual) {
      years = sorted;
    } else {
      months = sorted;
    }
  }
}

class PeriodComparison extends StatefulWidget {
  final ExecutiveApi api;
  final Filters filters;
  final ComparisonSelection? selection;
  const PeriodComparison({
    super.key,
    required this.api,
    required this.filters,
    this.selection,
  });
  @override
  State<PeriodComparison> createState() => _PeriodComparisonState();
}

class _PeriodComparisonState extends State<PeriodComparison> {
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  static const indicators = {
    'total': 'Registradas',
    'activas': 'Activas',
    'resueltas': 'Resueltas',
  };
  late final ComparisonSelection selection =
      widget.selection ?? ComparisonSelection();
  bool get annual => selection.annual;
  List<DateTime> get periods => selection.periods;
  Map<String, dynamic>? get result => selection.result;
  String indicator = 'total';
  int? focused;
  String? error;
  bool busy = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    if (result == null || selection.resultKey != queryKey) compare();
  }

  @override
  void didUpdateWidget(covariant PeriodComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (filtersKey(oldWidget.filters) != filtersKey(widget.filters)) compare();
  }

  String get queryKey =>
      '${filtersKey(widget.filters)}|$annual|${periods.map(iso).join(',')}';

  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String label(DateTime d) =>
      annual ? '${d.year}' : '${months[d.month - 1]} ${d.year}';
  String shortLabel(DateTime d) => annual
      ? '${d.year}'
      : '${months[d.month - 1].substring(0, 3)}\n${d.year}';
  DateTime start(DateTime d) => DateTime(d.year, annual ? 1 : d.month);
  DateTime end(DateTime d) =>
      annual ? DateTime(d.year, 12, 31) : DateTime(d.year, d.month + 1, 0);

  Future<void> compare() async {
    final current = ++generation;
    // Keep the previous result on screen while recomputing, so the card does
    // not collapse and shift the page.
    setState(() {
      busy = true;
      error = null;
    });
    final key = queryKey;
    try {
      final response = await widget.api.get('/ejecutivo/comparacion', {
        ...widget.filters,
        'inicio': [for (final p in periods) iso(start(p))],
        'fin': [for (final p in periods) iso(end(p))],
      });
      if (mounted && current == generation) {
        setState(() {
          selection.result = response;
          selection.resultKey = key;
          focused = null;
        });
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() {
          error = e.toString();
          selection.result = null;
        });
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  void use(List<DateTime> chosen) {
    setState(() => selection.periods = chosen);
    compare();
  }

  void mode(bool value) {
    if (annual == value) return;
    setState(() => selection.annual = value);
    compare();
  }

  /// Ready-made sets, so the usual comparisons take one tap.
  List<(String, List<DateTime>)> get presets {
    final now = DateTime.now();
    if (annual) {
      return [
        for (final n in [3, 5])
          (
            'Últimos $n años',
            [for (var i = n - 1; i >= 0; i--) DateTime(now.year - i)],
          ),
      ];
    }
    final last = DateTime(now.year, now.month - 1);
    return [
      for (final n in [3, 6, 12])
        (
          'Últimos $n meses',
          [
            for (var i = n - 1; i >= 0; i--)
              DateTime(last.year, last.month - i),
          ],
        ),
      (
        'Mismo mes en 3 años',
        [for (var i = 2; i >= 0; i--) DateTime(last.year - i, last.month)],
      ),
    ];
  }

  bool sameSet(List<DateTime> a, List<DateTime> b) =>
      a.length == b.length && a.every((d) => b.any((e) => same(d, e)));
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && (annual || a.month == b.month);

  Future<void> pick() async {
    final now = DateTime.now();
    final chosen = [...periods];
    var shownYear = periods.isEmpty ? now.year : periods.last.year;
    // Years are listed twelve at a time, ending with the current one.
    var lastYear = now.year;
    final result = await showPhoneSheet<List<DateTime>>(
      context,
      (sheet) => StatefulBuilder(
        builder: (sheet, update) {
          bool isChosen(DateTime d) => chosen.any((c) => same(c, d));
          void toggle(DateTime d) => update(() {
            if (isChosen(d)) {
              chosen.removeWhere((c) => same(c, d));
            } else if (chosen.length < ComparisonSelection.maxPeriods) {
              chosen.add(d);
            }
          });
          final full = chosen.length >= ComparisonSelection.maxPeriods;
          Widget option(DateTime d, String text, bool future) {
            final on = isChosen(d);
            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                backgroundColor: on ? blueTint : null,
                foregroundColor: ink,
                side: BorderSide(color: on ? salud : border),
              ),
              onPressed: future || (full && !on) ? null : () => toggle(d),
              icon: on
                  ? const Icon(Icons.check, size: 16, color: salud)
                  : const SizedBox.shrink(),
              label: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            );
          }

          Widget grid(List<Widget> children) => LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in children)
                  SizedBox(width: (constraints.maxWidth - 16) / 3, child: c),
              ],
            ),
          );
          Widget stepper(String text, VoidCallback? back, VoidCallback? next) =>
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: annual ? 'Años anteriores' : 'Año anterior',
                    onPressed: back,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(text, style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    tooltip: annual ? 'Años siguientes' : 'Año siguiente',
                    onPressed: next,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              );
          final sorted = [...chosen]..sort();
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      annual ? 'Años a comparar' : 'Meses a comparar',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Elige de 2 a ${ComparisonSelection.maxPeriods}. '
                      '${annual ? '' : 'Puedes mezclar meses de distintos años. '}'
                      'Se ordenan del más antiguo al más reciente.',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    if (annual)
                      stepper(
                        '${lastYear - 11} – $lastYear',
                        lastYear - 11 > 2000
                            ? () => update(() => lastYear -= 12)
                            : null,
                        lastYear < now.year
                            ? () => update(() => lastYear += 12)
                            : null,
                      )
                    else
                      stepper(
                        '$shownYear',
                        shownYear > 2000
                            ? () => update(() => shownYear--)
                            : null,
                        shownYear < now.year
                            ? () => update(() => shownYear++)
                            : null,
                      ),
                    grid([
                      if (annual)
                        for (var y = lastYear - 11; y <= lastYear; y++)
                          option(DateTime(y), '$y', false)
                      else
                        for (var m = 1; m <= 12; m++)
                          option(
                            DateTime(shownYear, m),
                            months[m - 1],
                            DateTime(shownYear, m).isAfter(now),
                          ),
                    ]),
                    const SizedBox(height: 16),
                    Text(
                      sorted.isEmpty
                          ? 'Sin periodos elegidos'
                          : '${sorted.length} elegidos: ${sorted.map(label).join(', ')}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    if (full)
                      const Text(
                        'Llegaste al máximo de periodos. Quita uno para elegir otro.',
                        style: TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: chosen.length < 2
                          ? null
                          : () => Navigator.pop(sheet, chosen),
                      child: Text(
                        chosen.length < 2
                            ? 'Elige al menos 2 periodos'
                            : 'Comparar ${chosen.length} periodos',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheet),
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    use(result);
  }

  String changeLabel(Map<String, dynamic>? variation) {
    if (variation == null) return '';
    final difference = variation['diferencia'] as num;
    if (difference == 0) return 'Sin cambio';
    final sign = difference > 0 ? '+' : '−';
    final percentage = variation['porcentaje'] as num?;
    return '$sign${difference.abs()}'
        '${percentage == null ? '' : ' (${percentage.abs().toStringAsFixed(1)} %)'}';
  }

  Widget periodRow(Map<String, dynamic> p, DateTime d, int i, bool first) {
    final total = p['total'] as num;
    final change =
        (p['variacion'] as Map?)?[indicator] as Map<String, dynamic>?;
    final difference = change?['diferencia'] as num? ?? 0;
    return InkWell(
      onTap: () => setState(() => focused = i),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: i == (focused ?? periods.length - 1) ? blueTint : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(d),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    total == 0
                        ? 'Sin solicitudes registradas'
                        : '$total registradas · ${p['activas']} activas · ${p['resueltas']} resueltas',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            if (!first)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    difference > 0
                        ? Icons.arrow_upward
                        : difference < 0
                        ? Icons.arrow_downward
                        : Icons.remove,
                    size: 14,
                    color: muted,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    changeLabel(change),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget results() {
    final rows = (result!['periodos'] as List).cast<Map<String, dynamic>>();
    // Only draw a result that belongs to the periods on screen.
    if (rows.length != periods.length) return const SizedBox.shrink();
    final values = [for (final r in rows) r[indicator] as num];
    final empty = [for (final r in rows) r['total'] == 0];
    final pick = focused ?? rows.length - 1;
    final name = indicators[indicator]!.toLowerCase();
    var peak = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[peak]) peak = i;
    }
    final average =
        values.fold<num>(0, (a, b) => a + b) /
        (values.isEmpty ? 1 : values.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        CopyExclude(
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(48, 40)),
            ),
            segments: [
              for (final e in indicators.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {indicator},
            onSelectionChanged: (v) => setState(() => indicator = v.first),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Solicitudes $name por periodo',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (empty.every((e) => e))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Sin solicitudes en los periodos elegidos. Prueba otras fechas o ajusta los filtros.',
              style: TextStyle(fontSize: 12),
            ),
          )
        else ...[
          Text(
            'Mayor: ${label(periods[peak])} (${values[peak]}) · '
            'Promedio: ${average.toStringAsFixed(average % 1 == 0 ? 0 : 1)} por periodo',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          if (empty.any((e) => e))
            Text(
              '${empty.where((e) => e).length} de ${empty.length} periodos sin registros; se muestran en 0.',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
        ],
        const SizedBox(height: 10),
        PeriodColumnsChart(
          labels: [for (final p in periods) label(p)],
          shortLabels: [for (final p in periods) shortLabel(p)],
          values: values,
          selected: pick,
          onSelect: (i) => setState(() => focused = i),
        ),
        const SizedBox(height: 14),
        const Text(
          'Detalle por periodo · el cambio es contra el periodo anterior',
          style: TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < rows.length; i++)
          periodRow(rows[i], periods[i], i, i == 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final unfinished = periods.any(
      (d) => d.year == now.year && (annual || d.month >= now.month),
    );
    return ExecutiveCard(
      copyable: true,
      title: 'Comparar periodos',
      source: 'Solicitudes registradas en cada periodo y su estatus actual. Cada periodo se compara con el anterior de la lista. Se conservan los filtros de municipio y catálogo; las fechas elegidas aquí sustituyen el rango general. Un aumento de volumen no implica una mejora.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CopyExclude(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(48, 48)),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('Meses')),
                ButtonSegment(value: true, label: Text('Años')),
              ],
              selected: {annual},
              onSelectionChanged: (values) => mode(values.first),
            ),
          ),
          const SizedBox(height: 12),
          CopyExclude(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Periodos a comparar (${periods.length} de ${ComparisonSelection.maxPeriods})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in periods)
                      InputChip(
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 12, color: ink),
                        label: Text(label(d)),
                        onPressed: pick,
                        // At least two periods stay, so there is something to compare.
                        onDeleted: periods.length > 2
                            ? () => use(periods.where((p) => p != d).toList())
                            : null,
                        deleteIcon: const Icon(Icons.close, size: 16),
                        deleteButtonTooltipMessage: 'Quitar ${label(d)}',
                      ),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.edit_calendar_outlined,
                        size: 16,
                        color: brand,
                      ),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: brand,
                        fontWeight: FontWeight.w700,
                      ),
                      label: Text(annual ? 'Elegir años' : 'Elegir meses'),
                      onPressed: pick,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Atajos',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (text, set) in presets)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 12, color: ink),
                        label: Text(text),
                        selected: sameSet(set, periods),
                        showCheckmark: false,
                        onSelected: (_) => use(set),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          Text(
            widget.filters.isNotEmpty
                ? 'Con los filtros del panel · actualización automática'
                : 'Todos los registros de tu estado · actualización automática',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          if (unfinished)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Incluye el periodo en curso: sus cifras pueden estar incompletas.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          if (busy && result != null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(
                minHeight: 2,
                semanticsLabel: 'Actualizando comparación',
              ),
            )
          else if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Actualizando comparación',
                ),
              ),
            ),
          if (error != null) ...[
            Notice(error!, error: true),
            OutlinedButton(onPressed: compare, child: const Text('Reintentar')),
          ],
          if (result != null) results(),
        ],
      ),
    );
  }
}
