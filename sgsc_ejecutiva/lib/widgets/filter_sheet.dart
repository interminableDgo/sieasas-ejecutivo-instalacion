import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'executive_widgets.dart';

/// Selected catalog ids per filter key. Values of one filter are alternatives
/// (any of them); different filters must all match.
typedef Filters = Map<String, List<String>>;

/// Label, query key and catalog key of each dashboard filter.
const filterDefinitions = [
  ['Municipio', 'municipio_id', 'municipios'],
  ['Tipo de apoyo', 'tipo_apoyo_id', 'apoyos'],
  ['Dependencia remitente', 'dependencia_id', 'dependencias'],
  ['Grupo vulnerable', 'grupo_vulnerable_id', 'grupos'],
  ['Estatus', 'estatus_id', 'estatus'],
];

Filters copyFilters(Filters filters) => {
  for (final e in filters.entries)
    if (e.value.isNotEmpty) e.key: [...e.value],
};

/// Order-insensitive identity, to compare selections and cache results.
String filtersKey(Filters filters) =>
    (filters.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => '${e.key}=${([...e.value]..sort()).join(',')}')
            .toList()
          ..sort())
        .join('&');

int filterCount(Filters filters) =>
    filters.values.fold(0, (n, values) => n + values.length);

String catalogName(Map<String, dynamic>? catalogs, String catalog, String id) {
  for (final r in (catalogs?[catalog] as List? ?? [])) {
    if ('${r['id']}' == id) return '${r['nombre']}';
  }
  return id;
}

String fold(String text) {
  const from = 'áéíóúüñ', to = 'aeiouun';
  final out = StringBuffer();
  for (final c in text.toLowerCase().split('')) {
    final i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString().trim();
}

/// Batch filtering: choices stay in a draft until "Ver N solicitudes", so the
/// dashboard does not reload on every change and the person knows how many
/// requests they will get before committing. Pops the new filters, or null.
class FilterSheet extends StatefulWidget {
  final Map<String, dynamic> catalogs;
  final Filters initial;
  final Future<int> Function(Filters filters) count;
  const FilterSheet({
    super.key,
    required this.catalogs,
    required this.initial,
    required this.count,
  });
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final Filters draft = copyFilters(widget.initial);
  int? matches;
  bool counting = false;
  int generation = 0;
  Timer? debounce;

  bool get dirty => filtersKey(draft) != filtersKey(widget.initial);

  @override
  void initState() {
    super.initState();
    recount();
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  void recount() {
    debounce?.cancel();
    setState(() => counting = true);
    debounce = Timer(const Duration(milliseconds: 250), () async {
      final current = ++generation;
      int? value;
      try {
        value = await widget.count(copyFilters(draft));
      } catch (_) {}
      if (!mounted || current != generation) return;
      setState(() {
        matches = value;
        counting = false;
      });
    });
  }

  void select(String key, List<String> ids) {
    setState(() {
      if (ids.isEmpty) {
        draft.remove(key);
      } else {
        draft[key] = [...ids];
      }
    });
    recount();
  }

  Future<void> confirmDiscard() async {
    if (await confirmAction(
          context,
          title: '¿Descartar cambios?',
          body: 'Los filtros que elegiste no se aplicarán. Los filtros actuales se conservan.',
          action: 'Descartar',
          destructive: true,
        ) &&
        mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> clearAll() async {
    final n = filterCount(draft);
    if (await confirmAction(
          context,
          title: '¿Quitar todos los filtros?',
          body:
              'Se quitarán $n ${n == 1 ? 'selección' : 'selecciones'}. '
              'El panel cambia hasta que pulses "Ver solicitudes".',
          action: 'Quitar todos',
          destructive: true,
        ) &&
        mounted) {
      setState(draft.clear);
      recount();
    }
  }

  Future<void> openPicker(List<String> def) async {
    final options = widget.catalogs[def[2]] as List? ?? [];
    await showPhoneSheet<void>(
      context,
      (_) => OptionPicker(
        title: def[0],
        options: [
          for (final r in options) (id: '${r['id']}', name: '${r['nombre']}'),
        ],
        initial: draft[def[1]] ?? const [],
        onChanged: (ids) => select(def[1], ids),
      ),
      heightFactor: 0.75,
    );
  }

  Widget field(List<String> def) {
    final options = widget.catalogs[def[2]] as List? ?? [];
    final selected = draft[def[1]] ?? const [];
    final names = [
      for (final id in selected) catalogName(widget.catalogs, def[2], id),
    ];
    return LabeledField(
      def[0],
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label:
                '${def[0]}: ${names.isEmpty ? 'Todos' : names.join(', ')}. Elegir opciones',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: options.isEmpty ? null : () => openPicker(def),
              child: InputDecorator(
                decoration: InputDecoration(
                  enabled: options.isNotEmpty,
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Text(
                  options.isEmpty
                      ? 'Sin opciones disponibles'
                      : names.isEmpty
                      ? 'Todos'
                      : names.length == 1
                      ? names.first
                      : '${names.length} seleccionados',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < selected.length; i++)
                  InputChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        names[i],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    deleteButtonTooltipMessage: 'Quitar ${names[i]}',
                    onDeleted: () => select(def[1], [...selected]..removeAt(i)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String get applyLabel {
    if (counting || matches == null) return 'Ver solicitudes';
    return matches == 1 ? 'Ver 1 solicitud' : 'Ver $matches solicitudes';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) confirmDiscard();
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Filtrar solicitudes'),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Puedes elegir varias opciones en cada filtro.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                ...filterDefinitions.map(field),
              ],
            ),
          ),
        ),
        SheetFooter(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                counting
                    ? 'Calculando resultados…'
                    : matches == 0
                    ? 'Ninguna solicitud coincide con esta combinación.'
                    : dirty
                    ? 'Los cambios se aplican al confirmar.'
                    : 'Sin cambios pendientes.',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Sized to its label so it never wraps on an iPhone SE.
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: draft.isEmpty ? null : clearAll,
                  child: const Text('Limpiar todo', maxLines: 1),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, copyFilters(draft)),
                    child: Text(applyLabel, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

/// Multi-select list for one filter: search, "Todos" and a checkbox per
/// option. Each tap is kept right away (nothing is lost if the sheet is
/// dismissed); "Listo" just closes. Searching never drops selections.
class OptionPicker extends StatefulWidget {
  final String title;
  final List<({String id, String name})> options;
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;
  const OptionPicker({
    super.key,
    required this.title,
    required this.options,
    required this.initial,
    required this.onChanged,
  });
  @override
  State<OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<OptionPicker> {
  late final List<String> selected = [...widget.initial];
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void toggle(String id) {
    setState(
      () => selected.contains(id) ? selected.remove(id) : selected.add(id),
    );
    widget.onChanged([...selected]);
  }

  void selectAll() {
    setState(selected.clear);
    widget.onChanged(const []);
  }

  @override
  Widget build(BuildContext context) {
    final q = fold(search.text);
    final visible = widget.options
        .where((o) => q.isEmpty || fold(o.name).contains(q))
        .toList();
    final searchable = widget.options.length > 8;
    return Padding(
      // Keep the list and "Listo" above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(widget.title),
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.title.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar búsqueda',
                          onPressed: () => setState(search.clear),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              selected.isEmpty
                  ? 'Sin selección: se incluyen todas las opciones.'
                  : '${selected.length} ${selected.length == 1 ? 'seleccionada' : 'seleccionadas'}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                if (q.isEmpty)
                  CheckboxListTile.adaptive(
                    value: selected.isEmpty,
                    onChanged: (_) => selectAll(),
                    title: const Text('Todos'),
                    controlAffinity: ListTileControlAffinity.leading,
                    // Brand orange on both platforms (iOS defaults to blue).
                    activeColor: brand,
                    dense: true,
                  ),
                for (final o in visible)
                  CheckboxListTile.adaptive(
                    value: selected.contains(o.id),
                    onChanged: (_) => toggle(o.id),
                    title: Text(o.name),
                    controlAffinity: ListTileControlAffinity.leading,
                    // Brand orange on both platforms (iOS defaults to blue).
                    activeColor: brand,
                    dense: true,
                  ),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sin coincidencias.',
                      style: TextStyle(color: muted),
                    ),
                  ),
              ],
            ),
          ),
          SheetFooter(
            children: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  selected.isEmpty ? 'Listo' : 'Listo (${selected.length})',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
