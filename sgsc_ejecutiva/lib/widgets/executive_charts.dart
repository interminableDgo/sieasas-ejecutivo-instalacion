import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

import '../core/theme.dart';
import 'executive_widgets.dart';

class DataBars extends StatelessWidget {
  final List<dynamic> rows;
  final Set<String> active;
  final ValueChanged<String> onSelect;
  const DataBars({
    super.key,
    required this.rows,
    this.active = const {},
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text(
        'Sin datos para mostrar.',
        style: TextStyle(color: muted),
      );
    }
    final max = rows.fold<double>(
      1,
      (n, r) => math.max(n, (r['total'] as num).toDouble()),
    );
    return Column(
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: r['id'] == null ? null : () => onSelect('${r['id']}'),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  color: active.contains('${r['id']}') ? blueTint : null,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${r['nombre']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${r['total']}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (r['total'] as num) / max,
                          minHeight: 8,
                          color: salud,
                          backgroundColor: paper,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class CategoryPieChart extends StatefulWidget {
  final String? selectedView;
  final ValueChanged<String>? onViewChanged;
  final List<dynamic> rows;
  final num total;
  final Set<String> active;
  final ValueChanged<String> onSelect;
  const CategoryPieChart({
    super.key,
    this.selectedView,
    this.onViewChanged,
    required this.rows,
    required this.total,
    required this.onSelect,
    this.active = const {},
  });

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  bool showAll = false;
  String view = 'Dona';

  static const colors = [
    salud,
    brand,
    Color(0xFF4E7D67),
    Color(0xFF8064A2),
    Color(0xFFD76770),
    Color(0xFF87949B),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final total = widget.total;
    if (rows.isEmpty || total == 0) {
      return const Text(
        'Sin datos para mostrar.',
        style: TextStyle(color: muted),
      );
    }
    final top = rows.take(5).toList();
    final otherTotal = rows
        .skip(5)
        .fold<num>(0, (sum, row) => sum + (row['total'] as num));
    final values = <num>[...top.map((row) => row['total'] as num)];
    final names = <String>[...top.map((row) => '${row['nombre']}')];
    final sum = values.fold<num>(0, (sum, value) => sum + value);
    final canStack =
        sum + otherTotal == total && values.every((value) => value >= 0);
    final chosen = widget.selectedView ?? view;
    final currentView = chosen == 'Apilada' && !canStack ? 'Dona' : chosen;
    final maximum = values.fold<num>(1, math.max);
    return Column(
      children: [
        CopyExclude(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final option in ['Dona', 'Barras', 'Apilada', 'Treemap'])
                    ChoiceChip(
                      label: Text(option == 'Apilada' ? 'Composición' : option),
                      selected: currentView == option,
                      onSelected: option == 'Apilada' && !canStack
                          ? null
                          : (_) {
                              setState(() => view = option);
                              widget.onViewChanged?.call(option);
                            },
                    ),
                ],
              ),
            ),
          ),
        ),
        if (currentView == 'Dona')
          SizedBox(
            height: 190,
            width: 190,
            child: CustomPaint(
              painter: _CategoryPiePainter(values, colors),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$sum',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      otherTotal > 0 ? 'mostradas' : 'solicitudes',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (currentView != 'Dona')
          Text(
            otherTotal > 0
                ? '$sum solicitudes mostradas'
                : '$total solicitudes',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        if (currentView == 'Barras')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Escala común: 0 a $maximum solicitudes',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ),
        if (currentView == 'Treemap') ...[
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: SizedBox(
              height: 190,
              width: double.infinity,
              child: CustomPaint(
                painter: _CategoryTreemapPainter(values, colors),
              ),
            ),
          ),
        ],
        if (currentView == 'Apilada') ...[
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: SizedBox(
              height: 28,
              width: double.infinity,
              child: CustomPaint(
                painter: _CategoryStackPainter(values, colors),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            otherTotal > 0
                ? 'Composición de las categorías mostradas'
                : 'Composición del total · 100%',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
        const SizedBox(height: 12),
        ...List.generate(values.length, (i) {
          final row = i < top.length ? top[i] : null;
          final selected =
              row != null && widget.active.contains('${row['id']}');
          final percent = total == 0 ? 0 : values[i] / total * 100;
          return InkWell(
            onTap: row == null || row['id'] == null
                ? null
                : () => widget.onSelect('${row['id']}'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          names[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${values[i]} · ${percent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (currentView == 'Barras') ...[
                    const SizedBox(height: 6),
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                        value: (values[i] / maximum).clamp(0.0, 1.0),
                        minHeight: 10,
                        color: colors[i],
                        backgroundColor: paper,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        if (otherTotal > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Fuera de la gráfica: $otherTotal solicitudes en ${rows.length - 5} categorías. '
              'Total: $total. Porcentajes sobre el total; áreas sobre las $sum mostradas.',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ),
        if (rows.length > 5) ...[
          if (showAll) ...[
            const Divider(height: 20),
            ...rows.skip(5).map((row) {
              final selected = widget.active.contains('${row['id']}');
              final percent = (row['total'] as num) / total * 100;
              return InkWell(
                onTap: row['id'] == null
                    ? null
                    : () => widget.onSelect('${row['id']}'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          '${row['nombre']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${row['total']} · ${percent.toStringAsFixed(1)}%",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          CopyExclude(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => showAll = !showAll),
                icon: Icon(
                  showAll ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  showAll ? 'Ver menos' : 'Ver todos (${rows.length})',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Uses exactly the same ordered values and palette as the donut and legend.
class _CategoryTreemapPainter extends CustomPainter {
  final List<num> values;
  final List<Color> colors;
  const _CategoryTreemapPainter(this.values, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    void draw(int start, int end, Rect rect) {
      final sum = values.sublist(start, end).fold<num>(0, (a, b) => a + b);
      if (sum <= 0) return;
      if (end - start == 1) {
        canvas.drawRect(rect, Paint()..color = colors[start]);
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final label = TextPainter(
          text: TextSpan(
            text: '${values[start]}',
            style: TextStyle(
              fontFamily: 'Mulish',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: colors[start].computeLuminance() > 0.179
                  ? Colors.black
                  : Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (rect.width >= label.width + 4 && rect.height >= label.height + 4) {
          label.paint(
            canvas,
            rect.center - Offset(label.width / 2, label.height / 2),
          );
        }
        return;
      }
      final mid = (start + end) ~/ 2;
      final fraction =
          values.sublist(start, mid).fold<num>(0, (a, b) => a + b) / sum;
      if (rect.width >= rect.height) {
        final cut = rect.left + rect.width * fraction;
        draw(start, mid, Rect.fromLTRB(rect.left, rect.top, cut, rect.bottom));
        draw(mid, end, Rect.fromLTRB(cut, rect.top, rect.right, rect.bottom));
      } else {
        final cut = rect.top + rect.height * fraction;
        draw(start, mid, Rect.fromLTRB(rect.left, rect.top, rect.right, cut));
        draw(mid, end, Rect.fromLTRB(rect.left, cut, rect.right, rect.bottom));
      }
    }

    draw(0, values.length, Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant _CategoryTreemapPainter old) =>
      !listEquals(values, old.values) || !listEquals(colors, old.colors);
}

class _CategoryStackPainter extends CustomPainter {
  final List<num> values;
  final List<Color> colors;
  const _CategoryStackPainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final sum = values.fold<num>(0, (sum, value) => sum + value);
    if (sum <= 0) return;
    double left = 0;
    for (var i = 0; i < values.length; i++) {
      final width = size.width * values[i] / sum;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width, size.height),
        Paint()..color = colors[i],
      );
      left += width;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryStackPainter old) =>
      !listEquals(values, old.values) || !listEquals(colors, old.colors);
}

class _CategoryPiePainter extends CustomPainter {
  final List<num> values;
  final List<Color> colors;
  const _CategoryPiePainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final sum = values.fold<num>(0, (total, value) => total + value);
    if (sum == 0) return;
    final center = size.center(Offset.zero);
    final outer = Rect.fromCircle(
      center: center,
      radius: size.shortestSide / 2 - 10,
    );
    final inner = Rect.fromCircle(
      center: center,
      radius: size.shortestSide * .29,
    );
    final largest = values.indexOf(values.reduce((a, b) => a > b ? a : b));
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / sum * math.pi * 2;
      final mid = start + sweep / 2;
      final offset = i == largest && values.where((v) => v > 0).length > 1
          ? Offset(math.cos(mid), math.sin(mid)) * 8
          : Offset.zero;
      final path = Path()
        ..arcTo(outer.shift(offset), start, sweep, true)
        ..arcTo(inner.shift(offset), start + sweep, -sweep, false)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter old) =>
      !listEquals(values, old.values) || !listEquals(colors, old.colors);
}

/// One column per compared period, all on a common scale from 0, so several
/// months or years read at a glance. A period without records keeps its
/// place with a flat mark and "0" instead of disappearing from the axis.
/// Tapping a column selects it; the caller shows its detail.
class PeriodColumnsChart extends StatelessWidget {
  final List<String> labels, shortLabels;
  final List<num> values;
  final int selected;
  final ValueChanged<int> onSelect;
  const PeriodColumnsChart({
    super.key,
    required this.labels,
    required this.shortLabels,
    required this.values,
    required this.selected,
    required this.onSelect,
  });

  static const barArea = 150.0;

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<num>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          maximum == 0
              ? 'Todos los periodos registran 0.'
              : 'Escala común desde 0 · máximo $maximum',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10, color: muted),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  label: '${labels[i]}: ${values[i]}',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${values[i]}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: values[i] == 0 ? muted : ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: values[i] == 0 || maximum == 0
                                ? 3
                                : math.max(4, values[i] / maximum * barArea),
                            constraints: const BoxConstraints(maxWidth: 44),
                            decoration: BoxDecoration(
                              color: values[i] == 0
                                  ? border
                                  : i == selected
                                  ? salud
                                  : salud.withValues(alpha: 0.4),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                          Container(height: 1, color: border),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              shortLabels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.2,
                                fontWeight: i == selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: i == selected ? ink : muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class TrendChart extends StatefulWidget {
  final List<dynamic> points;
  const TrendChart({super.key, required this.points});
  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final hasData = points.any(
      (p) => (p['recibidas'] as num) > 0 || (p['resueltas'] as num) > 0,
    );
    if (!hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 25),
        child: Text(
          'Todavía no hay movimientos en los últimos 12 meses.',
          style: TextStyle(color: muted),
        ),
      );
    }
    return Column(
      children: [
        const Wrap(
          spacing: 18,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.horizontal_rule, color: salud),
                Text('Registradas', style: TextStyle(fontSize: 11)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.horizontal_rule, color: brand),
                Text('Resueltas actualmente', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => GestureDetector(
            onTapDown: (event) => setState(
              () => selected =
                  ((event.localPosition.dx - 28) /
                          (box.maxWidth - 44) *
                          (points.length - 1))
                      .round()
                      .clamp(0, points.length - 1),
            ),
            child: SizedBox(
              height: 185,
              width: double.infinity,
              child: CustomPaint(painter: _TrendPainter(points, selected)),
            ),
          ),
        ),
        if (selected != null && selected! < points.length)
          Text(
            '${points[selected!]['mes']} · ${points[selected!]['recibidas']} registradas · ${points[selected!]['resueltas']} resueltas actualmente',
            style: const TextStyle(fontSize: 11),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<dynamic> points;
  final int? selected;
  _TrendPainter(this.points, this.selected);
  void label(
    Canvas canvas,
    String value,
    Offset position, {
    Color color = muted,
  }) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontFamily: 'Mulish', fontSize: 9, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final max = points.fold<double>(
      1,
      (m, p) => math.max(
        m,
        math.max(
          (p['recibidas'] as num).toDouble(),
          (p['resueltas'] as num).toDouble(),
        ),
      ),
    );
    final plot = Rect.fromLTRB(28, 10, size.width - 16, size.height - 28);
    for (var i = 0; i < 5; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()..color = border,
      );
      label(canvas, (max * i / 4).toStringAsFixed(0), Offset(0, y - 5));
    }
    for (final key in ['recibidas', 'resueltas']) {
      final color = key == 'recibidas' ? salud : brand;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x = plot.left + plot.width * i / math.max(1, points.length - 1);
        final y = plot.bottom - plot.height * (points[i][key] as num) / max;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(
          Offset(x, y),
          selected == i ? 4 : 2,
          Paint()..color = color,
        );
        if (key == 'recibidas' && (i % 3 == 0 || i == points.length - 1)) {
          label(
            canvas,
            '${points[i]['mes']}'.substring(2),
            Offset(x - 13, plot.bottom + 10),
          );
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

/// The dashboard owns active municipality ids; the map owns only its viewport.
class MunicipalityMap extends StatefulWidget {
  /// Dashboard rows: {id, nombre, total}.
  final List<dynamic> rows;

  /// Catalog rows: {id, nombre, clave_inegi}; links INEGI shapes to ids.
  final List<dynamic> catalog;
  final Set<String> active;
  final num? activeCount, resolvedCount;
  final ValueChanged<String?> onFilter;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  const MunicipalityMap({
    super.key,
    required this.rows,
    required this.catalog,
    required this.onFilter,
    this.active = const {},
    this.activeCount,
    this.resolvedCount,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  @override
  State<MunicipalityMap> createState() => _MunicipalityMapState();
}

class _MapShape {
  final String cvegeo, name;
  final Path path;
  _MapShape(this.cvegeo, this.name, this.path);
}

class _MapData {
  final double width, height;
  final String source;
  final List<_MapShape> shapes;
  _MapData(this.width, this.height, this.source, this.shapes);
}

class _MunicipalityMapState extends State<MunicipalityMap> {
  late final Future<_MapData> _data = rootBundle
      .loadString('assets/nl-municipios.json', cache: false)
      .then((raw) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return _MapData(
          (json['ancho'] as num).toDouble(),
          (json['alto'] as num).toDouble(),
          '${json['fuente']}',
          [
            for (final m in json['municipios'] as List)
              _MapShape(
                '${m['cvegeo']}',
                '${m['nombre']}',
                parseSvgPathData('${m['path']}')
                  ..fillType = PathFillType.evenOdd,
              ),
          ],
        );
      });
  String? get selected {
    if (widget.active.length != 1) return null;
    for (final entry in idByCvegeo.entries) {
      if (widget.active.contains(entry.value)) return entry.key;
    }
    return null;
  }

  bool zoomed = true;

  /// Pinch (or the +/− buttons) zoom; names appear as municipalities get
  /// big enough on screen, as in map apps.
  final zoom = TransformationController();
  double get zoomLevel => zoom.value.getMaxScaleOnAxis();
  static const maxZoom = 8.0;

  @override
  void initState() {
    super.initState();
    zoom.addListener(_zoomChanged);
  }

  void _zoomChanged() => setState(() {});

  @override
  void dispose() {
    zoom
      ..removeListener(_zoomChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MunicipalityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.active, widget.active)) {
      zoomed = true;
      zoom.value = Matrix4.identity();
    }
  }

  /// Zooms by [factor] around the centre of the map of [size].
  void zoomBy(double factor, Size size) {
    final current = zoomLevel;
    final next = (current * factor).clamp(1.0, maxZoom);
    if (next == current) return;
    final center = Offset(size.width / 2, size.height / 2);
    // Keep the point at the centre of the view in place.
    final focus = zoom.toScene(center);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-focus.dx, -focus.dy, 0, 1);
    zoom.value = next == 1 ? Matrix4.identity() : matrix;
  }

  Map<String, String> get idByCvegeo => {
    for (final r in widget.catalog)
      if (r['clave_inegi'] != null && r['id'] != null)
        '${r['clave_inegi']}': '${r['id']}',
  };
  Map<String, num> get totalById => {
    for (final r in widget.rows) '${r['id']}': r['total'] as num,
  };

  Rect viewBox(_MapData data) {
    final full = Rect.fromLTWH(0, 0, data.width, data.height);
    if (!zoomed || selected == null) return full;
    final bounds = data.shapes
        .where((s) => s.cvegeo == selected)
        .firstOrNull
        ?.path
        .getBounds();
    if (bounds == null) return full;
    // A window with the map's aspect, ~1/3 of its size, centred on the pick.
    final w = math.min(
      data.width,
      math.max(
        data.width / 3,
        math.max(bounds.width, bounds.height * data.width / data.height) * 1.6,
      ),
    );
    final h = w * data.height / data.width;
    final left = (bounds.center.dx - w / 2).clamp(0.0, data.width - w);
    final top = (bounds.center.dy - h / 2).clamp(0.0, data.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Size of the drawn map, for zooming around its centre with the buttons.
  Size mapSize = Size.zero;

  @override
  Widget build(BuildContext context) => FutureBuilder<_MapData>(
    future: _data,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (snapshot.hasError) {
        return const SizedBox(
          height: 240,
          child: Center(
            child: Text('No se pudo cargar el mapa de municipios.'),
          ),
        );
      }
      if (data == null) {
        return const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator.adaptive()),
        );
      }
      final ids = idByCvegeo, totals = totalById;
      num count(String cvegeo) => totals[ids[cvegeo]] ?? 0;
      final max = data.shapes.fold<num>(
        1,
        (m, s) => math.max(m, count(s.cvegeo)),
      );
      final pick = selected == null
          ? null
          : data.shapes.where((s) => s.cvegeo == selected).firstOrNull;
      final activeCvegeo = {
        for (final e in ids.entries)
          if (widget.active.contains(e.value)) e.key,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the map and with the same rows before and after a tap, so
          // the answer is in view and the map never shifts under the finger.
          Semantics(
            liveRegion: true,
            child: Text(
              pick?.name ?? 'Toca un municipio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: SizedBox(
              height: 48,
              child: Text(
                widget.loading
                    ? 'Actualizando solicitudes...'
                    : widget.error != null
                    ? 'No se pudieron actualizar los datos.'
                    : pick == null
                    ? 'Toca un municipio para filtrar. Acerca el mapa '
                          '(pellizca o usa + y −) para ver los nombres.'
                    : count(pick.cvegeo) == 0
                    ? 'Sin solicitudes con los filtros actuales.'
                    : '${count(pick.cvegeo)} solicitudes; toca de nuevo para quitar'
                          '${widget.activeCount == null ? '' : '\n${widget.activeCount} activas (incluye pendientes) · ${widget.resolvedCount} resueltas'}',
                maxLines: 2,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ),
          SizedBox(
            height: 4,
            child: widget.loading ? const LinearProgressIndicator() : null,
          ),
          CopyExclude(
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  if (widget.active.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => widget.onFilter(null),
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Quitar municipio',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (pick != null)
                    IconButton(
                      tooltip: zoomed ? 'Ver todo el estado' : 'Acercar',
                      onPressed: () => setState(() {
                        zoomed = !zoomed;
                        zoom.value = Matrix4.identity();
                      }),
                      icon: Icon(zoomed ? Icons.zoom_out_map : Icons.zoom_in),
                    ),
                  if (widget.active.isEmpty) const Spacer(),
                  IconButton(
                    key: const ValueKey('map-zoom-out'),
                    tooltip: 'Alejar mapa',
                    onPressed: zoomLevel <= 1
                        ? null
                        : () => zoomBy(1 / 1.6, mapSize),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    key: const ValueKey('map-zoom-in'),
                    tooltip: 'Acercar mapa',
                    onPressed: zoomLevel >= maxZoom
                        ? null
                        : () => zoomBy(1.6, mapSize),
                    icon: const Icon(Icons.add),
                  ),
                  if (widget.error != null)
                    IconButton(
                      tooltip: 'Reintentar mapa',
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final height = math.min(
                420.0,
                box.maxWidth * data.height / data.width,
              );
              final width = height * data.width / data.height;
              mapSize = Size(width, height);
              return Center(
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: viewBox(data)),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, view, _) => Semantics(
                    container: true,
                    label: widget.loading
                        ? 'Actualizando solicitudes del mapa.'
                        : widget.error != null
                        ? 'No se pudieron actualizar los datos del mapa.'
                        : pick == null
                        ? 'Mapa de Nuevo León por municipio. Toca un municipio para filtrar sus solicitudes.'
                        : 'Mapa de Nuevo León. ${pick.name}: ${count(pick.cvegeo)} solicitudes.',
                    // Described, but not exposed as one big button: on web
                    // with accessibility on, a tap on a semantic button is
                    // delivered at its centre, which would always pick the
                    // central municipality. The bar list is the accessible
                    // way to choose one.
                    child: ExcludeSemantics(
                      child: ClipRect(
                        child: InteractiveViewer(
                          transformationController: zoom,
                          minScale: 1,
                          maxScale: maxZoom,
                          // At full view one-finger drags scroll the page;
                          // once zoomed in, they move the map.
                          panEnabled: zoomLevel > 1.01,
                          child: Listener(
                            // A mouse wheel over the map keeps scrolling the
                            // panel (Ctrl + wheel zooms), so the map never
                            // traps the page on a computer.
                            onPointerSignal: (event) {
                              if (event is! PointerScrollEvent ||
                                  HardwareKeyboard.instance.isControlPressed) {
                                return;
                              }
                              final page = Scrollable.maybeOf(context);
                              if (page == null) return;
                              GestureBinding.instance.pointerSignalResolver
                                  .register(
                                    event,
                                    (e) => page.position.pointerScroll(
                                      (e as PointerScrollEvent).scrollDelta.dy,
                                    ),
                                  );
                            },
                            child: GestureDetector(
                              onTapUp: (event) {
                                final v = view;
                                final point =
                                    v.topLeft +
                                    event.localPosition * (v.width / width);
                                for (final shape in data.shapes) {
                                  if (shape.path.contains(point)) {
                                    final id = ids[shape.cvegeo];
                                    if (id != null) {
                                      widget.onFilter(
                                        shape.cvegeo == selected ? null : id,
                                      );
                                    }
                                    return;
                                  }
                                }
                              },
                              child: CustomPaint(
                                key: const ValueKey('municipality-map'),
                                size: Size(width, height),
                                painter: _MunicipalityPainter(
                                  data.shapes,
                                  view!,
                                  zoom: zoomLevel,
                                  labeled: {?selected},
                                  fill: (s) {
                                    final value = count(s.cvegeo);
                                    if (s.cvegeo == selected) return brand;
                                    if (widget.loading ||
                                        widget.error != null) {
                                      return border;
                                    }
                                    return value == 0
                                        ? border
                                        : brand.withValues(
                                            alpha: 0.15 + 0.55 * value / max,
                                          );
                                  },
                                  outlined: {...activeCvegeo, ?selected},
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          if (!widget.loading && widget.error == null) const _MapLegend(),
          const SizedBox(height: 8),
          Text(
            'Límites municipales: ${data.source}.',
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ],
      );
    },
  );
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Menos', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          Container(
            width: 72,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  brand.withValues(alpha: 0.15),
                  brand.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('Más', style: TextStyle(fontSize: 11)),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          const Text('Sin solicitudes', style: TextStyle(fontSize: 11)),
        ],
      ),
    ],
  );
}

class _MunicipalityPainter extends CustomPainter {
  final List<_MapShape> shapes;
  final Rect view;
  final Color Function(_MapShape) fill;
  final Set<String> outlined;

  /// Pinch zoom of the map; names are sized for the screen, not the map.
  final double zoom;

  /// Always named when they fit (the selected municipality).
  final Set<String> labeled;
  _MunicipalityPainter(
    this.shapes,
    this.view, {
    required this.fill,
    required this.outlined,
    this.zoom = 1,
    this.labeled = const {},
  });

  /// Screen size of the names, in logical pixels.
  static const labelSize = 11.0;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / view.width;
    canvas
      ..scale(scale)
      ..translate(-view.left, -view.top);
    for (final shape in shapes) {
      canvas.drawPath(shape.path, Paint()..color = fill(shape));
      canvas.drawPath(
        shape.path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 / scale,
      );
    }
    for (final shape in shapes.where((s) => outlined.contains(s.cvegeo))) {
      canvas.drawPath(
        shape.path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 / scale,
      );
    }
    paintNames(canvas, scale * zoom);
  }

  /// Names of the municipalities big enough on screen to hold them, the
  /// selected one and the largest first, skipping any that would overlap.
  /// Zooming in reveals more names, as in map apps.
  void paintNames(Canvas canvas, double pixelsPerUnit) {
    final order = [...shapes]
      ..sort((a, b) {
        final pick = (labeled.contains(b.cvegeo) ? 1 : 0).compareTo(
          labeled.contains(a.cvegeo) ? 1 : 0,
        );
        if (pick != 0) return pick;
        final ra = a.path.getBounds(), rb = b.path.getBounds();
        return (rb.width * rb.height).compareTo(ra.width * ra.height);
      });
    final placed = <Rect>[];
    final fontSize = labelSize / pixelsPerUnit;
    for (final shape in order) {
      final bounds = shape.path.getBounds();
      final text = TextPainter(
        text: TextSpan(
          text: shape.name,
          style: TextStyle(
            fontFamily: 'Mulish',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (text.width > bounds.width * 0.95 ||
          text.height > bounds.height * 0.6) {
        text.dispose();
        continue;
      }
      var center = bounds.center;
      if (!shape.path.contains(center)) {
        // Concave shapes: try a little up and down before giving up.
        center = [
          for (final f in [-0.2, 0.2, -0.35, 0.35])
            bounds.center + Offset(0, bounds.height * f),
        ].firstWhere(shape.path.contains, orElse: () => bounds.center);
      }
      final box = Rect.fromCenter(
        center: center,
        width: text.width + 4 / pixelsPerUnit,
        height: text.height + 2 / pixelsPerUnit,
      );
      if (placed.any(box.overlaps)) {
        text.dispose();
        continue;
      }
      placed.add(box);
      final at = center - Offset(text.width / 2, text.height / 2);
      // A white halo keeps the name readable over any shade of orange.
      final halo = TextPainter(
        text: TextSpan(
          text: shape.name,
          style: TextStyle(
            fontFamily: 'Mulish',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 / pixelsPerUnit
              ..color = Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      halo.paint(canvas, at);
      text.paint(canvas, at);
      halo.dispose();
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _MunicipalityPainter old) => true;
}
