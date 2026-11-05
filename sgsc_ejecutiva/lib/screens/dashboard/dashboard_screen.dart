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

  /// Text of the table search; it narrows only the table, not the charts.
  String search = '';
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
  };

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
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () {
              if (mounted) applyFilters(previous);
            },
          ),
        ),
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

  /// Parts that add up to the total. The two closing statuses only appear
  /// when they have requests, so the sentence stays short.
  static String statusBreakdown(Map<String, dynamic> s) {
    final notCompetent = s['no_competencia'] as num? ?? 0;
    final cancelled = s['canceladas'] as num? ?? 0;
    return [
      '${s['activas']} activas (incluye pendientes)',
      '${s['resueltas']} resueltas',
      if (notCompetent > 0)
        '$notCompetent ${notCompetent == 1 ? 'no es' : 'no son'} competencia',
      if (cancelled > 0)
        '$cancelled ${cancelled == 1 ? 'cerrada o cancelada' : 'cerradas o canceladas'}',
    ].join(' · ');
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
      source: 'Solicitudes que cumplen los filtros del panel. La búsqueda considera beneficiario, solicitante, tipo de apoyo, estatus, fecha de registro y folio, sin importar acentos ni mayúsculas. Cada palabra afina el resultado (por ejemplo, «jorge vacunación») y sólo afecta a esta tabla.',
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
                        : 'No hay solicitudes que coincidan con «$search».',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            )
          else ...[
            if (search.isNotEmpty)
              Text(
                '$total ${total == 1 ? 'resultado' : 'resultados'} para «$search»',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
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
                      columnSpacing: 18,
                      horizontalMargin: 12,
                      dataRowMaxHeight: 64,
                      headingTextStyle: cellStyle.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      dataTextStyle: cellStyle,
                      columns: [
                        const DataColumn(
                          label: SizedBox(
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
                          'Fecha de registro',
                          'Beneficiario',
                          'Solicitante',
                          'Municipio',
                          'Tipo de apoyo',
                          'Remitente',
                        ])
                          DataColumn(label: Text(h)),
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
                                  ),
                                ),
                                onTap: () =>
                                    openDetail(r['solicitud_id'] as int),
                              ),
                              for (final (value, width) in [
                                (r['folio'], null),
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
          Row(
            children: [
              const Expanded(
                child: Text('Ámbito estatal', style: TextStyle(fontSize: 12)),
              ),
              if (refreshing)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Actualizando…',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              TextButton.icon(
                onPressed: catalogs == null ? null : openFilters,
                icon: const Icon(Icons.tune, size: 16),
                label: Text(
                  active.isEmpty ? 'Filtros' : 'Filtros (${active.length})',
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
                for (final f in shown)
                  InputChip(
                    label: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: chipWidth),
                      child: Text(
                        filterLabel(f.key, f.id),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
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
                      if (catalogs != null)
                        OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => showComparison = !showComparison),
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
                          ExecutiveCard(
                            copyable: true,
                            title: 'Solicitudes registradas',
                            source: 'Cantidad de solicitudes del estado asignado que cumplen los filtros. No representa personas únicas ni apoyos entregados. Activas incluye todos los estatus que no son Resuelto, Resuelto con observación, Cerrado / Cancelado o No es competencia. Pendientes puede ser una parte de las activas.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${summary!['total']}',
                                  style: const TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.w800,
                                    color: salud,
                                  ),
                                ),
                                const Text(
                                  'Total según los filtros seleccionados',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  statusBreakdown(summary!),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Nothing to search when no request meets the filters.
                          if (hasData) requestsTable(),
                          if (!hasData)
                            ExecutiveCard(
                              title: filters.isEmpty
                                  ? 'Aún no hay solicitudes'
                                  : 'Sin resultados',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Icon(
                                    Icons.inbox_outlined,
                                    size: 46,
                                    color: muted,
                                  ),
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
                                      filters.isEmpty
                                          ? 'Registrar primera solicitud'
                                          : 'Limpiar filtros',
                                    ),
                                  ),
                                ],
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
                          // The map asset covers Nuevo León (INEGI 19).
                          if ('${widget.user['clave_inegi']}' == '19')
                            ExecutiveCard(
                              copyable: true,
                              key: const ValueKey('municipality-map-card'),
                              title: 'Mapa de solicitudes por municipio',
                              source:
                                  'Municipios de Nuevo León coloreados según la cantidad de solicitudes con los filtros actuales. '
                                  'Toca un municipio para filtrar y acercar; vuelve a tocarlo para quitarlo. '
                                  'Límites municipales: INEGI, Marco Geoestadístico.',
                              child: MunicipalityMap(
                                rows: group('municipios'),
                                catalog: catalogs?['municipios'] as List? ?? [],
                                active: {...?filters['municipio_id']},
                                activeCount:
                                    (filters['municipio_id']?.length ?? 0) == 1
                                    ? summary!['activas'] as num
                                    : null,
                                resolvedCount:
                                    (filters['municipio_id']?.length ?? 0) == 1
                                    ? summary!['resueltas'] as num
                                    : null,
                                onFilter: selectMapMunicipality,
                                loading: loading,
                                error: error,
                                onRetry: load,
                              ),
                            ),
                          bars(
                            'Solicitudes por municipio',
                            'municipios',
                            'municipio_id',
                            'Solicitudes agrupadas por municipio. Toca una barra para aplicar el filtro.',
                          ),
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
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
          decoration: const BoxDecoration(
            color: paper,
            border: Border(top: BorderSide(color: border)),
          ),
          // One neutral entry point: format is chosen and confirmed in the
          // export sheet, so no button looks "selected" by colour alone.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: !hasData || loading || exporting || error != null
                    ? null
                    : openExport,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Exportar reporte'),
              ),
              if (!hasData && !loading && error == null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Disponible cuando haya solicitudes.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
