import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

import '../core/theme.dart';

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
  final List<dynamic> rows;
  final num total;
  final Set<String> active;
  final ValueChanged<String> onSelect;
  const CategoryPieChart({
    super.key,
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
    final values = <num>[
      ...top.map((row) => row['total'] as num),
      if (otherTotal > 0) otherTotal,
    ];
    final names = <String>[
      ...top.map((row) => '${row['nombre']}'),
      if (otherTotal > 0) 'Otros',
    ];
    return Column(
      children: [
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
                    '$total',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'solicitudes',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
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
              child: Row(
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
            ),
          );
        }),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => showAll = !showAll),
              icon: Icon(
                showAll ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(showAll ? 'Ver menos' : 'Ver todos (${rows.length})'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryPiePainter extends CustomPainter {
  final List<num> values;
  final List<Color> colors;
  const _CategoryPiePainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final sum = values.fold<num>(0, (total, value) => total + value);
    if (sum == 0) return;
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / sum * math.pi * 2;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = colors[i]);
      start += sweep;
    }
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width * 0.29,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter old) =>
      !listEquals(values, old.values) || !listEquals(colors, old.colors);
}

/// Side-by-side period comparison for independent indicators. A grouped bar
/// chart makes the two periods directly comparable without implying that the
/// indicators are steps in a continuous series.
class PeriodComparisonChart extends StatelessWidget {
  final Map<String, dynamic> earlier, later;
  final Map<String, dynamic> variations;
  final String earlierLabel, laterLabel;
  const PeriodComparisonChart({
    super.key,
    required this.earlier,
    required this.later,
    required this.variations,
    required this.earlierLabel,
    required this.laterLabel,
  });

  @override
  Widget build(BuildContext context) {
    const indicators = [
      ('Solicitudes registradas', 'total'),
      ('Activas', 'activas'),
      ('Resueltas', 'resueltas'),
    ];
    final maxValue = indicators.fold<num>(0, (maximum, item) {
      final key = item.$2;
      return math.max(
        maximum,
        math.max(earlier[key] as num, later[key] as num),
      );
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cada par de barras compara el mismo indicador entre periodos.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 10),
        const Text(
          'Las barras comparan los conteos; el cambio porcentual va junto a cada indicador.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _ChartLegend(color: muted, label: earlierLabel),
            _ChartLegend(color: salud, label: laterLabel),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            maxValue == 0
                ? 'Los dos periodos registran 0.'
                : 'Escala común desde 0: $maxValue',
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ),
        const SizedBox(height: 4),
        for (final (label, key) in indicators)
          _PeriodIndicatorBars(
            label: label,
            earlier: earlier[key] as num,
            later: later[key] as num,
            variation: variations[key] as Map<String, dynamic>,
            maximum: maxValue,
          ),
      ],
    );
  }
}

class _PeriodIndicatorBars extends StatelessWidget {
  final String label;
  final num earlier, later, maximum;
  final Map<String, dynamic> variation;
  const _PeriodIndicatorBars({
    required this.label,
    required this.earlier,
    required this.later,
    required this.variation,
    required this.maximum,
  });

  String get changeLabel {
    final difference = variation['diferencia'] as num;
    if (difference == 0) return 'Sin cambio';
    final sign = difference > 0 ? '+' : '−';
    final percentage = variation['porcentaje'] as num?;
    final percentLabel = percentage == null
        ? '% sin referencia'
        : '$sign${percentage.abs().toStringAsFixed(1)}%';
    return 'Δ $sign${difference.abs()} · $percentLabel';
  }

  Widget bar(num value, Color color) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: maximum == 0 ? 0 : (value / maximum).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: paper,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: label == 'Solicitudes registradas' ? blueTint : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  changeLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          bar(earlier, muted),
          bar(later, salud),
        ],
      ),
    ),
  );
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _ChartLegend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
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
  @override
  void didUpdateWidget(covariant MunicipalityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.active, widget.active)) zoomed = true;
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
                    ? 'Toca para filtrar y acercar.'
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
          SizedBox(
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
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text(
                        'Quitar municipio',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                if (pick != null)
                  IconButton(
                    tooltip: zoomed ? 'Ver todo el estado' : 'Acercar',
                    onPressed: () => setState(() => zoomed = !zoomed),
                    icon: Icon(zoomed ? Icons.zoom_out_map : Icons.zoom_in),
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
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final height = math.min(
                420.0,
                box.maxWidth * data.height / data.width,
              );
              final width = height * data.width / data.height;
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
                        child: ClipRect(
                          child: CustomPaint(
                            key: const ValueKey('municipality-map'),
                            size: Size(width, height),
                            painter: _MunicipalityPainter(
                              data.shapes,
                              view!,
                              fill: (s) {
                                final value = count(s.cvegeo);
                                if (s.cvegeo == selected) return brand;
                                if (widget.loading || widget.error != null) {
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
  _MunicipalityPainter(
    this.shapes,
    this.view, {
    required this.fill,
    required this.outlined,
  });
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
  }

  @override
  bool shouldRepaint(covariant _MunicipalityPainter old) => true;
}
