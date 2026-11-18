import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/theme.dart';
import '../../services/executive_api.dart';
import '../../widgets/executive_widgets.dart';
import '../../widgets/executive_charts.dart';
import '../../widgets/export_sheet.dart';
import '../../widgets/filter_sheet.dart';
import '../../widgets/period_comparison.dart';
import '../../widgets/request_search.dart';
import '../solicitudes/nueva_solicitud_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ExecutiveApi api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const DashboardScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? summary, catalogs, detail;
  List<dynamic> rows = [];
  final Filters filters = {};
  // Lives here, not in the comparison widget, so hiding it keeps the periods.
  final comparison = ComparisonSelection();
  bool showAllChips = false;
  static const collapsedChips = 3;
  String screen = 'dashboard';
  String? error, message;
  bool loading = true, exporting = false;
  String supportView = 'Dona', groupView = 'Dona';
  static const chartCodes = {
    'Dona': 'donut',
    'Barras': 'bars',
    'Apilada': 'stacked',
    'Treemap': 'treemap',
  };
  bool showComparison = false;
  int page = 0, total = 0, generation = 0, rowsGeneration = 0;

  /// The panel has two parts: indicators ('resumen') and the list of
  /// requests ('solicitudes'). Separating them keeps the summary short enough
  /// to scroll through, and makes clear that the search finds requests.
  String tab = 'resumen';

  /// Municipalities card: ranked list (answers "which has more") or map.
  String municipalityView = 'Lista';

  /// Text of the table search; it narrows only the table, not the charts.
  String search = '';

  /// Server sort key of each table column, in order. The server sorts, so
  /// the order covers every page and not only the rows on screen.
  static const sortKeys = [
    'estatus',
    'solicitud',
    'antiguedad',
    'fecha',
    'beneficiario',
    'solicitante',
    'municipio',
    'tipo_apoyo',
    'remitente',
  ];
  int sortColumn = 3; // Newest registrations first.
  bool sortAscending = false;
  bool loadingRows = false;
  final Set<String> expanded = {};
  static const topRows = 5;
  @override
  void initState() {
    super.initState();
    load();
  }

  final scroll = ScrollController();
  // Horizontal scroll of the requests table when its columns do not fit.
  final tableScroll = ScrollController();
  final topKey = GlobalKey(), barKey = GlobalKey();
  double? barHeight;

  @override
  void dispose() {
    scroll.dispose();
    tableScroll.dispose();
    super.dispose();
  }

  /// When the pinned bar changes height (chips appear, the panel opens) while
  /// it is stuck at the top, move the offset by the same amount so the content
  /// the person was looking at does not jump.
  void keepContentAnchored(Duration _) {
    final bar = barKey.currentContext?.findRenderObject() as RenderBox?;
    final top = topKey.currentContext?.findRenderObject() as RenderBox?;
    if (bar == null || !bar.hasSize || !scroll.hasClients) return;
    final previous = barHeight;
    barHeight = bar.size.height;
    if (previous == null || previous == barHeight) return;
    final position = scroll.position;
    final pinned = top != null && top.hasSize
        ? position.pixels >= top.size.height - 0.5
        : position.pixels > 0;
    if (!pinned) return;
    scroll.jumpTo(
      (position.pixels + barHeight! - previous).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Future<void> load() async {
    final current = ++generation;
    // A search typed while this loads must not be replaced by older rows.
    final currentRows = ++rowsGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final Map<String, Object> query = {...filters};
      final results = await Future.wait([
        widget.api.get('/ejecutivo/dashboard', query),
        widget.api.get('/ejecutivo/solicitudes', rowsQuery()),
        if (catalogs == null) widget.api.get('/ejecutivo/catalogos'),
      ]);
      if (!mounted || current != generation) return;
      setState(() {
        summary = results[0];
        if (currentRows == rowsGeneration) {
          rows = results[1]['items'] as List;
          total = results[1]['total'] as int;
          loadingRows = false;
        }
        if (results.length > 2) catalogs = results[2];
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      if (e is ApiException && e.status == 401) {
        widget.onLogout();
        return;
      }
      setState(() => error = e.toString());
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Map<String, Object> rowsQuery() => {
    ...filters,
    'page': '$page',
    if (search.isNotEmpty) 'q': search,
    // Age is the registration date read backwards: youngest = newest.
    'orden': sortKeys[sortColumn] == 'antiguedad'
        ? 'fecha'
        : sortKeys[sortColumn],
    'direccion': (sortAscending != (sortKeys[sortColumn] == 'antiguedad'))
        ? 'asc'
        : 'desc',
  };

  void sortRows(int column, bool ascending) {
    setState(() {
      sortColumn = column;
      sortAscending = ascending;
    });
    page = 0;
    loadRows();
  }

  /// Reloads only the table (search and pages) so the charts stay put.
  Future<void> loadRows() async {
    final current = ++rowsGeneration;
    setState(() => loadingRows = true);
    try {
      final result = await widget.api.get(
        '/ejecutivo/solicitudes',
        rowsQuery(),
      );
      if (!mounted || current != rowsGeneration) return;
      setState(() {
        rows = result['items'] as List;
        total = result['total'] as int;
      });
    } catch (e) {
      if (!mounted || current != rowsGeneration) return;
      if (e is ApiException && e.status == 401) {
        widget.onLogout();
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo consultar la tabla. Intenta de nuevo.'),
        ),
      );
    } finally {
      if (mounted && current == rowsGeneration) {
        setState(() => loadingRows = false);
      }
    }
  }

  void searchRows(String text) {
    search = text;
    page = 0;
    loadRows();
  }

  static String shortDate(Object? value) {
    final date = DateTime.tryParse('$value');
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  void applyFilters(Filters next, {String? undo}) {
    final previous = copyFilters(filters);
    setState(() {
      filters
        ..clear()
        ..addAll(copyFilters(next));
      page = 0;
    });
    if (undo != null) offerUndo(undo, previous);
    load();
  }

  /// Tapping a bar adds its value to that filter, or removes it if present.
  void toggleFilter(String key, String id) {
    final next = copyFilters(filters);
    final values = next.putIfAbsent(key, () => []);
    final removing = values.remove(id);
    if (!removing) values.add(id);
    applyFilters(next, undo: removing ? 'Filtro quitado' : null);
  }

  void selectMapMunicipality(String? id) {
    final next = copyFilters(filters)..remove('municipio_id');
    if (id != null) next['municipio_id'] = [id];
    applyFilters(next);
  }

  void removeFilter(String key, String id) {
    final next = copyFilters(filters);
    next[key]?.remove(id);
    applyFilters(next, undo: 'Filtro quitado');
  }

  void clear() {
    if (filters.isEmpty) return;
    applyFilters({}, undo: 'Filtros limpiados');
  }

  Future<void> openFilters() async {
    final result = await showPhoneSheet<Filters>(
      context,
      (_) => FilterSheet(
        catalogs: catalogs ?? {},
        initial: copyFilters(filters),
        count: (draft) async =>
            (await widget.api.get('/ejecutivo/solicitudes', {
                  ...draft,
                  'page': '0',
                }))['total']
                as int,
        optionCounts: (catalog, others) async {
          final result = await widget.api.get('/ejecutivo/dashboard', {
            ...others,
          });
          return {
            for (final r in (result[catalog] as List? ?? []))
              '${r['id']}': r['total'] as num,
          };
        },
      ),
    );
    if (result == null ||
        !mounted ||
        filtersKey(result) == filtersKey(filters)) {
      return;
    }
    final removed = filters.entries.any(
      (e) => e.value.any((id) => !(result[e.key]?.contains(id) ?? false)),
    );
    applyFilters(result, undo: removed ? 'Filtros actualizados' : null);
  }

  /// One line per active filter, e.g. "Municipio: Apodaca, Linares".
  List<String> filterSummary() => [
    'Periodo de registro: ${periodSummary(filters)}',
    for (final def in filterDefinitions)
      if (filters[def[1]]?.isNotEmpty ?? false)
        '${def[0]}: ${filters[def[1]]!.map((id) => catalogName(catalogs, def[2], id)).join(', ')}',
  ];

  Future<void> openExport() async {
    final format = await showPhoneSheet<String>(
      context,
      (_) => ExportSheet(
        total: (summary?['total'] as num? ?? 0).toInt(),
        appliedFilters: filterSummary(),
        onExport: export,
      ),
    );
    if (format == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Reporte ${exportFormats[format]!.$1} generado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void offerUndo(String text, Filters previous) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // At the bottom, where the system shows its messages; nothing is
          // fixed there any more since «Exportar» moved up.
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ink.withValues(alpha: 0.88),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          // Snack bars with an action stay until dismissed by default; this
          // one leaves on its own after 3 s.
          persist: false,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            textColor: brand,
            label: 'Deshacer',
            onPressed: () {
              if (mounted) applyFilters(previous);
            },
          ),
        ),
      );
  }

  /// "Municipio: **Hidalgo**": the value, which is what matters, in bold.
  TextSpan filterLabelSpan(String key, String id) {
    final label = filterLabel(key, id);
    final split = label.indexOf(': ');
    if (split < 0) return TextSpan(text: label);
    return TextSpan(
      children: [
        TextSpan(
          text: label.substring(0, split + 2),
          style: const TextStyle(color: muted),
        ),
        TextSpan(
          text: label.substring(split + 2),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  String filterLabel(String key, String id) {
    if (key == 'fecha_inicio') return 'Desde: $id';
    if (key == 'fecha_fin') return 'Hasta: $id';
    for (final def in filterDefinitions) {
      if (def[1] == key) {
        return '${def[0]}: ${catalogName(catalogs, def[2], id)}';
      }
    }
    return '$key: $id';
  }

  /// "Reporte ejecutivo SIESAS 2026-11-04 15.30.pdf": the date sorts in
  /// file lists and the time tells apart several exports of the same day.
  static String reportFileName(String format, DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Reporte ejecutivo SIESAS ${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}.${two(at.minute)}.$format';
  }

  /// Returns null on success, '' if the person cancelled, or the error.
  Future<String?> export(String format) async {
    setState(() => exporting = true);
    try {
      final bytes = await widget.api.export(format, {
        ...filters,
        'chart_apoyos': chartCodes[supportView]!,
        'chart_grupos': chartCodes[groupView]!,
      });
      final name = reportFileName(format, DateTime.now());
      final file = XFile.fromData(
        bytes,
        name: name,
        mimeType: format == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (kIsWeb) {
        await file.saveTo(name);
      } else if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        if (!mounted) return '';
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [file],
            fileNameOverrides: [name],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } else {
        final location = await getSaveLocation(suggestedName: name);
        if (location == null) return '';
        await file.saveTo(location.path);
      }
      return null;
    } catch (e) {
      return 'No se pudo exportar el reporte. ${e is ApiException ? e.message : 'Intenta nuevamente.'}';
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> openDetail(int id) async {
    setState(() {
      screen = 'detail';
      detail = null;
      error = null;
    });
    try {
      final value = await widget.api.get('/ejecutivo/solicitudes/$id');
      if (mounted) setState(() => detail = value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> logout() async {
    try {
      await widget.api.post('/auth/logout', {});
    } catch (_) {}
    if (mounted) widget.onLogout();
  }

  void back() {
    setState(() {
      screen = 'dashboard';
      error = null;
    });
    load();
  }

  List<dynamic> group(String key) => summary?[key] as List? ?? [];

  /// Requests of the current filters, searchable by beneficiary, applicant
  /// or registration date.
  Widget requestsTable() {
    const cellStyle = TextStyle(fontFamily: 'Mulish', color: ink, fontSize: 11);
    final pages = (total / 10).ceil();
    return ExecutiveCard(
      key: const ValueKey('requests-table-card'),
      title: 'Detalle de solicitudes',
      source: 'Solicitudes que cumplen los filtros del panel. La búsqueda considera beneficiario, solicitante, tipo de apoyo, estatus, fecha de registro y folio, sin importar acentos ni mayúsculas. Cada palabra afina el resultado (por ejemplo, «jorge vacunación») y solo afecta a esta tabla.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RequestSearchField(
            api: widget.api,
            initial: search,
            scope: () => {...filters},
            onSearch: searchRows,
            onOpen: openDetail,
          ),
          SizedBox(
            height: 4,
            child: loadingRows ? const LinearProgressIndicator() : null,
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    search.isEmpty
                        ? 'No hay solicitudes para mostrar.'
                        : filters.isEmpty
                        ? 'No hay solicitudes que coincidan con «$search».'
                        : 'No hay solicitudes de «$search» con los filtros aplicados.',
                    style: const TextStyle(color: muted),
                  ),
                  // A filter set earlier can hide what is searched: say so
                  // and offer to search the whole state.
                  if (search.isNotEmpty && filters.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Notice(
                      'Estás filtrando por ${filterSummary().skip(1).join('; ')}. '
                      'Quita los filtros para buscar en todo el estado.',
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('search-without-filters'),
                      onPressed: () =>
                          applyFilters({}, undo: 'Filtros quitados'),
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Buscar sin filtros'),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            if (search.isNotEmpty)
              Text(
                '$total ${total == 1 ? 'resultado' : 'resultados'} para «$search»',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            // On a phone there is no hover: the meaning of the status icons
            // and of their number is written here instead of in a tooltip.
            const StatusLegend(),
            // The table spans the whole card on wide screens; when its
            // columns do not fit, long names wrap to two lines and a visible
            // scrollbar shows there is more to the right.
            LayoutBuilder(
              builder: (context, box) => Scrollbar(
                controller: tableScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: tableScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: DataTable(
                      sortColumnIndex: sortColumn,
                      sortAscending: sortAscending,
                      columnSpacing: 18,
                      horizontalMargin: 12,
                      dataRowMaxHeight: 64,
                      headingTextStyle: cellStyle.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      dataTextStyle: cellStyle,
                      columns: [
                        DataColumn(
                          onSort: sortRows,
                          tooltip: 'Ordenar por estado',
                          label: const SizedBox(
                            width: 44,
                            child: Center(
                              child: Text(
                                'Estado',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        for (final h in [
                          'Solicitud',
                          'Antigüedad',
                          'Fecha de registro',
                          'Beneficiario',
                          'Solicitante',
                          'Municipio',
                          'Tipo de apoyo',
                          'Remitente',
                        ])
                          DataColumn(
                            label: Text(h),
                            tooltip: 'Ordenar por ${h.toLowerCase()}',
                            onSort: sortRows,
                          ),
                      ],
                      rows: [
                        for (final r in rows)
                          DataRow(
                            cells: [
                              DataCell(
                                Center(
                                  child: StatusDaysIcon(
                                    status: '${r['estatus']}',
                                    registeredAt: r['fecha_registro'],
                                    showDays: false,
                                  ),
                                ),
                                onTap: () =>
                                    openDetail(r['solicitud_id'] as int),
                              ),
                              for (final (value, width) in [
                                (r['folio'], null),
                                (
                                  StatusDaysIcon.ageLabel(
                                    '${r['estatus']}',
                                    r['fecha_registro'],
                                  ),
                                  null,
                                ),
                                (shortDate(r['fecha_registro']), null),
                                (r['beneficiario'] ?? '', 170.0),
                                (r['solicitante'] ?? '', 150.0),
                                (r['municipio'], 130.0),
                                (r['tipo_apoyo'], 130.0),
                                (r['dependencia'], 170.0),
                              ])
                                DataCell(
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: width ?? double.infinity,
                                    ),
                                    child: Text(
                                      '$value',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onTap: () =>
                                      openDetail(r['solicitud_id'] as int),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Toca una solicitud para consultar el detalle.',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: page == 0 || loadingRows
                      ? null
                      : () {
                          page--;
                          loadRows();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${page + 1} / $pages',
                  style: const TextStyle(fontSize: 12),
                ),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: (page + 1) * 10 >= total || loadingRows
                      ? null
                      : () {
                          page++;
                          loadRows();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      style: const TextStyle(
        color: brand,
        fontSize: 11,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  /// Top [topRows] rows, plus active ones that fall outside, unless the
  /// card was expanded with "Ver todos".
  List<dynamic> visibleRows(String dataKey, String filterKey) {
    final all = group(dataKey);
    if (expanded.contains(dataKey) || all.length <= topRows) return all;
    final top = all.take(topRows).toList();
    final active = filters[filterKey] ?? const [];
    top.addAll(all.skip(topRows).where((r) => active.contains('${r['id']}')));
    return top;
  }

  Widget moreToggle(String dataKey) {
    final count = group(dataKey).length;
    if (count <= topRows) return const SizedBox.shrink();
    final open = expanded.contains(dataKey);
    return CopyExclude(
      child: TextButton.icon(
        onPressed: () => setState(
          () => open ? expanded.remove(dataKey) : expanded.add(dataKey),
        ),
        icon: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
        label: Text(open ? 'Ver menos' : 'Ver todos ($count)'),
      ),
    );
  }

  Widget bars(String title, String dataKey, String filterKey, String source) =>
      ExecutiveCard(
        copyable: true,
        title: title,
        source: source,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DataBars(
              rows: visibleRows(dataKey, filterKey),
              active: {...?filters[filterKey]},
              onSelect: (v) => toggleFilter(filterKey, v),
            ),
            moreToggle(dataKey),
          ],
        ),
      );

  /// Total and its parts, written as before the usability test (one sentence
  /// under the total). Only the numbers change: bold and in their status
  /// colour (green resolved, red closed, amber active, dark grey for «no es
  /// competencia», which is not an error), so they no longer blend into grey.
  /// Closing statuses appear only when they have requests.
  Widget summaryCard() {
    final s = summary!;
    num part(String key) => s[key] as num? ?? 0;
    final notCompetent = part('no_competencia'), cancelled = part('canceladas');
    final parts = [
      (
        'activas',
        statusTextColor(StatusKind.pending),
        part('activas'),
        'activas (incluye pendientes)',
      ),
      ('resueltas', statusGreen, part('resueltas'), 'resueltas'),
      if (notCompetent > 0)
        (
          'no_competencia',
          ink,
          notCompetent,
          notCompetent == 1 ? 'no es competencia' : 'no son competencia',
        ),
      if (cancelled > 0)
        (
          'canceladas',
          statusRed,
          cancelled,
          cancelled == 1 ? 'cerrada o cancelada' : 'cerradas o canceladas',
        ),
    ];
    return ExecutiveCard(
      copyable: true,
      key: const ValueKey('summary-card'),
      title: 'Solicitudes registradas',
      source: 'Cantidad de solicitudes del estado asignado que cumplen los filtros. No representa personas únicas ni apoyos entregados. Activas incluye todos los estatus que no son Resuelto, Resuelto con observación, Cerrado / Cancelado o No es competencia. Pendientes puede ser una parte de las activas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The number says its scope: the whole state, or the filtered set.
          Text.rich(
            key: const ValueKey('summary-total'),
            TextSpan(
              children: [
                TextSpan(
                  text: '${s['total']}',
                  style: const TextStyle(fontSize: 42),
                ),
                TextSpan(
                  text: filters.isEmpty
                      ? ' totales en ${widget.user['entidad'] ?? 'el estado'}'
                      : (s['total'] as num) == 1
                      ? ' solicitud filtrada'
                      : ' solicitudes filtradas',
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
            style: const TextStyle(fontWeight: FontWeight.w800, color: salud),
          ),
          const SizedBox(height: 10),
          Text.rich(
            key: const ValueKey('summary-breakdown'),
            TextSpan(
              children: [
                for (final (i, (_, color, value, label)) in parts.indexed) ...[
                  if (i > 0) const TextSpan(text: ' · '),
                  TextSpan(
                    text: '$value',
                    semanticsLabel: '$value',
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                  ),
                  TextSpan(text: ' $label'),
                ],
              ],
            ),
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  /// One card answers "where": ranked list first (the answer at a glance),
  /// map as an alternative view, so the map no longer pushes the list down.
  Widget municipalityCard() {
    final hasMap = '${widget.user['clave_inegi']}' == '19';
    final view = hasMap ? municipalityView : 'Lista';
    return ExecutiveCard(
      copyable: true,
      key: const ValueKey('municipality-card'),
      title: 'Solicitudes por municipio',
      source: view == 'Lista'
          ? 'Municipios ordenados de más a menos solicitudes con los filtros actuales. Toca una barra para aplicar el filtro.'
          : 'Municipios de Nuevo León coloreados según la cantidad de solicitudes con los filtros actuales. '
                'Toca un municipio para filtrar y acercar; vuelve a tocarlo para quitarlo. '
                'Límites municipales: INEGI, Marco Geoestadístico.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMap)
            CopyExclude(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  key: const ValueKey('municipality-view'),
                  spacing: 6,
                  children: [
                    for (final option in ['Lista', 'Mapa'])
                      ChoiceChip(
                        label: Text(option),
                        selected: view == option,
                        onSelected: (_) =>
                            setState(() => municipalityView = option),
                      ),
                  ],
                ),
              ),
            ),
          if (view == 'Lista') ...[
            DataBars(
              rows: visibleRows('municipios', 'municipio_id'),
              active: {...?filters['municipio_id']},
              onSelect: (v) => toggleFilter('municipio_id', v),
            ),
            moreToggle('municipios'),
          ] else
            MunicipalityMap(
              key: const ValueKey('municipality-map-card'),
              rows: group('municipios'),
              catalog: catalogs?['municipios'] as List? ?? [],
              active: {...?filters['municipio_id']},
              activeCount: (filters['municipio_id']?.length ?? 0) == 1
                  ? summary!['activas'] as num
                  : null,
              resolvedCount: (filters['municipio_id']?.length ?? 0) == 1
                  ? summary!['resueltas'] as num
                  : null,
              onFilter: selectMapMunicipality,
              loading: loading,
              error: error,
              onRetry: load,
            ),
        ],
      ),
    );
  }

  /// No request meets the filters (or none registered yet).
  Widget emptyCard() => ExecutiveCard(
    title: filters.isEmpty ? 'Aún no hay solicitudes' : 'Sin resultados',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.inbox_outlined, size: 46, color: muted),
        const SizedBox(height: 14),
        Text(
          filters.isEmpty
              ? 'Las solicitudes de tu estado aparecerán aquí cuando se registren.'
              : 'No hay solicitudes que coincidan con los filtros seleccionados.',
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: filters.isEmpty
              ? () => setState(() => screen = 'new')
              : clear,
          child: Text(
            filters.isEmpty ? 'Registrar primera solicitud' : 'Limpiar filtros',
          ),
        ),
      ],
    ),
  );

  /// Two parts of the panel, always visible in the pinned bar.
  Widget tabs() => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: SegmentedButton<String>(
      key: const ValueKey('panel-tabs'),
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: blueTint,
        selectedForegroundColor: ink,
        minimumSize: const Size(0, 44),
      ),
      segments: [
        const ButtonSegment(
          value: 'resumen',
          label: Text('Resumen'),
          icon: Icon(Icons.dashboard_outlined, size: 18),
        ),
        ButtonSegment(
          value: 'solicitudes',
          label: Text(
            summary == null
                ? 'Solicitudes'
                : 'Solicitudes (${summary!['total']})',
          ),
          icon: const Icon(Icons.list_alt_outlined, size: 18),
        ),
      ],
      selected: {tab},
      onSelectionChanged: (value) => selectTab(value.first),
    ),
  );

  void selectTab(String value) {
    if (value == tab) return;
    setState(() => tab = value);
    // Each part starts at its top, right under the pinned bar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final top = topKey.currentContext?.findRenderObject() as RenderBox?;
      if (!scroll.hasClients || top == null || !top.hasSize) return;
      final pinned = top.size.height;
      if (scroll.offset > pinned) scroll.jumpTo(pinned);
    });
  }

  /// Pinned bar: filter toggle, active filters and a discreet progress line,
  /// so selections never lose sight of what is applied.
  Widget filterBar(BuildContext context) {
    final refreshing = loading && summary != null;
    final active = [
      for (final key in ['fecha_inicio', 'fecha_fin'])
        for (final id in filters[key] ?? const <String>[]) (key: key, id: id),
      for (final def in filterDefinitions)
        for (final id in filters[def[1]] ?? const <String>[])
          (key: def[1], id: id),
    ];
    final shown = showAllChips ? active : active.take(collapsedChips).toList();
    final chipWidth = MediaQuery.sizeOf(context).width - 110;
    return Container(
      key: barKey,
      color: paper,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tabs(),
          if (refreshing)
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Actualizando…',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ),
          // Filter, then export: the two steps of a report, side by side.
          // The applied filters appear right below, so the person sees what
          // the report will contain.
          Row(
            children: [
              // A button like the app's others (white, grey border, as
              // «Nueva solicitud»), so it does not look like the orange
              // filter chips under it; the count sits in an orange badge.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('filters-button'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onPressed: catalogs == null ? null : openFilters,
                  icon: const Icon(Icons.tune, size: 18, color: brand),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Filtros'),
                      if (active.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: brand,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${active.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: ink, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('export-button'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed:
                      summary == null ||
                          (summary!['total'] as num) == 0 ||
                          exporting ||
                          error != null
                      ? null
                      : openExport,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  // Two lines so both fit on a phone: what (and whether
                  // it is filtered), then the file formats.
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filters.isEmpty
                            ? 'Exportar reporte'
                            : 'Exportar filtrado',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const Text(
                        'PDF o Excel',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Wrapped, never a hidden horizontal scroll: the first few are
          // shown and "Ver todos" reveals the rest on more lines.
          if (active.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Said once, so the chips read as an active filter and not
                // as a tag: everything below is limited to them.
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Text(
                    'Filtrando por:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: brand,
                    ),
                  ),
                ),
                for (final f in shown)
                  InputChip(
                    backgroundColor: brandTint,
                    side: const BorderSide(color: brand),
                    deleteIconColor: brand,
                    label: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: chipWidth),
                      child: Text.rich(
                        filterLabelSpan(f.key, f.id),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: ink),
                      ),
                    ),
                    deleteButtonTooltipMessage: 'Quitar filtro',
                    onDeleted: () => removeFilter(f.key, f.id),
                  ),
                if (active.length > collapsedChips)
                  TextButton(
                    onPressed: () =>
                        setState(() => showAllChips = !showAllChips),
                    child: Text(
                      showAllChips
                          ? 'Ver menos'
                          : 'Ver todos (${active.length})',
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          SizedBox(
            height: 2,
            child: refreshing
                ? const LinearProgressIndicator(minHeight: 2)
                : const Divider(height: 2, thickness: 1, color: border),
          ),
        ],
      ),
    );
  }

  Widget profile() => SingleChildScrollView(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading('Mi perfil', onBack: back),
        ExecutiveCard(
          title: '${widget.user['nombres']} ${widget.user['apellidos']}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                backgroundColor: blueTint,
                radius: 30,
                child: Icon(Icons.person_outline, color: salud, size: 32),
              ),
              const SizedBox(height: 16),
              Text('${widget.user['correo']}'),
              const Text('Rol · Ejecutivo'),
              const SizedBox(height: 14),
              Text(
                'Estado asignado: ${widget.user['entidad']}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Consulta estatal de todas las dependencias. El estado lo asigna la administración.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: logout,
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );

  Widget detailView() => SingleChildScrollView(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading('Detalle de solicitud', onBack: back),
        if (error != null)
          Notice(error!, error: true)
        else if (detail == null)
          const Center(child: CircularProgressIndicator.adaptive())
        else ...[
          ExecutiveCard(
            title: '${detail!['folio']}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${detail!['nombres']} ${detail!['apellidos']}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                ...{
                  'Municipio': 'municipio',
                  'Tipo de apoyo': 'tipo_apoyo',
                  'Dependencia remitente': 'dependencia',
                  'Grupo vulnerable': 'grupo_vulnerable',
                  'Registrada': 'fecha_registro',
                  'Canal': 'canal',
                  'Unidad tratante': 'unidad_tratante',
                  'Origen': 'origen',
                  'Solicitante': 'solicitante',
                }.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                        Text('${detail![e.value] ?? 'Sin información'}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ExecutiveCard(
            title: 'Descripción',
            child: Text('${detail!['descripcion'] ?? 'Sin descripción'}'),
          ),
          ExecutiveCard(
            title: 'Observaciones',
            child: Text(
              '${detail!['observaciones'] ?? 'Sin observaciones registradas.'}',
            ),
          ),
        ],
      ],
    ),
  );

  /// Profile, detail and new request are views of this screen, not routes:
  /// Android's back button (and iOS back swipe on a route) must return to the
  /// panel instead of closing the app.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: screen == 'dashboard',
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: view(context),
  );

  Widget view(BuildContext context) {
    if (screen == 'profile') return profile();
    if (screen == 'detail') return detailView();
    if (screen == 'new') {
      return NewRequestScreen(
        api: widget.api,
        catalogs: catalogs ?? {},
        entity: '${widget.user['entidad']}',
        onBack: back,
        onSaved: (folio) {
          setState(() {
            screen = 'dashboard';
            message = '$folio registrada correctamente';
            filters.clear();
            page = 0;
          });
          load();
        },
      );
    }
    final hasData = summary != null && (summary!['total'] as num) > 0;
    WidgetsBinding.instance.addPostFrameCallback(keepContentAnchored);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: load,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    key: topKey,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Panel ejecutivo · ${widget.user['entidad']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Solicitudes registradas',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Mi perfil',
                              onPressed: () =>
                                  setState(() => screen = 'profile'),
                              icon: const Icon(Icons.person_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: catalogs == null || loading
                              ? null
                              : () => setState(() => screen = 'new'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nueva solicitud'),
                        ),
                      ],
                    ),
                  ),
                ),
                PinnedHeaderSliver(child: filterBar(context)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  sliver: SliverList.list(
                    children: [
                      if (message != null) Notice(message!),
                      if (error != null) ...[
                        Notice(error!, error: true),
                        OutlinedButton.icon(
                          onPressed: load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Only the first load shows a spinner; later refreshes keep the
                      // content mounted so the scroll position is not lost.
                      if (summary == null && loading)
                        const Padding(
                          padding: EdgeInsets.all(36),
                          child: Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        ),
                    ],
                  ),
                ),
                if (summary != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                    // A sliver list (not a Column) keeps one semantics node
                    // per card for screen readers.
                    sliver: SliverAnimatedOpacity(
                      opacity: loading ? 0.6 : 1,
                      duration: const Duration(milliseconds: 150),
                      sliver: SliverList.list(
                        children: [
                          if ((summary!['datos_demo'] as num? ?? 0) > 0)
                            Notice(
                              'Este panel incluye ${summary!['datos_demo']} solicitudes ficticias de prueba, identificadas con folios DEMO-COMP-.',
                            ),
                          if (tab == 'resumen') ...[
                            summaryCard(),
                            if (!hasData) emptyCard(),
                            // Shown even without data: the map keeps "Quitar
                            // municipio" when a filter leaves no requests.
                            ...[
                              municipalityCard(),
                              ExecutiveCard(
                                copyable: true,
                                title: 'Apoyos solicitados',
                                source: 'Se grafican los cinco tipos más frecuentes; las demás categorías se indican por separado. Los porcentajes se calculan sobre todas las solicitudes que cumplen los filtros. Toca una categoría para filtrar.',
                                child: CategoryPieChart(
                                  selectedView: supportView,
                                  onViewChanged: (value) =>
                                      setState(() => supportView = value),
                                  rows: group('apoyos'),
                                  total: summary!['total'] as num,
                                  active: {...?filters['tipo_apoyo_id']},
                                  onSelect: (id) =>
                                      toggleFilter('tipo_apoyo_id', id),
                                ),
                              ),
                              ExecutiveCard(
                                copyable: true,
                                title: 'Clasificación por grupo vulnerable',
                                source: 'Distribución de solicitudes por grupo vulnerable. Los porcentajes se calculan sobre las solicitudes clasificadas en el catálogo, incluida la categoría Sin información. Un mismo beneficiario puede generar varias solicitudes. Toca una categoría para aplicar el filtro.',
                                child: CategoryPieChart(
                                  selectedView: groupView,
                                  onViewChanged: (value) =>
                                      setState(() => groupView = value),
                                  rows: group('grupos'),
                                  total: group('grupos').fold<num>(
                                    0,
                                    (sum, row) => sum + (row['total'] as num),
                                  ),
                                  active: {...?filters['grupo_vulnerable_id']},
                                  onSelect: (id) =>
                                      toggleFilter('grupo_vulnerable_id', id),
                                ),
                              ),
                              ExecutiveCard(
                                copyable: true,
                                title: 'Solicitudes por mes de registro',
                                source: 'Últimos 12 meses. Solicitudes registradas en cada mes y cuántas están resueltas actualmente. No indica el mes en que se resolvieron.',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    heading('TENDENCIA · ÚLTIMOS 12 MESES'),
                                    TrendChart(points: group('tendencia')),
                                  ],
                                ),
                              ),
                              if (catalogs != null)
                                OutlinedButton.icon(
                                  key: const ValueKey('comparison-toggle'),
                                  onPressed: () => setState(
                                    () => showComparison = !showComparison,
                                  ),
                                  icon: const Icon(Icons.compare_arrows),
                                  label: Text(
                                    showComparison
                                        ? 'Ocultar comparación'
                                        : 'Comparar meses o años',
                                  ),
                                ),
                              if (catalogs != null && showComparison)
                                PeriodComparison(
                                  api: widget.api,
                                  filters: copyFilters(filters),
                                  selection: comparison,
                                ),
                            ],
                          ] else ...[
                            // Nothing to search when no request meets the filters.
                            if (hasData) requestsTable() else emptyCard(),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
