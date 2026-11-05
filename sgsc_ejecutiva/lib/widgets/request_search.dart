import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/executive_api.dart';

/// Search box of the requests table. While typing it offers the most recent
/// matching requests (with what tells them apart: type of support, date and
/// status), the people involved and the total, never a long list. The server
/// ignores accents and capitals, so "jose perez" also finds "José Pérez".
class RequestSearchField extends StatefulWidget {
  final ExecutiveApi api;

  /// Current dashboard filters, so suggestions lead to rows in the table.
  final Map<String, Object> Function() scope;
  final String initial;
  final ValueChanged<String> onSearch;

  /// Opens one request chosen from the suggestions.
  final ValueChanged<int> onOpen;
  const RequestSearchField({
    super.key,
    required this.api,
    required this.scope,
    required this.onSearch,
    required this.onOpen,
    this.initial = '',
  });

  @override
  State<RequestSearchField> createState() => _RequestSearchFieldState();
}

class _RequestSearchFieldState extends State<RequestSearchField> {
  static const typingPause = Duration(milliseconds: 400);
  late final controller = TextEditingController(text: widget.initial);
  final focus = FocusNode();
  Timer? typing;
  String applied = '', asked = '';
  int total = 0, shownRequests = 0;

  @override
  void initState() {
    super.initState();
    applied = widget.initial.trim();
    controller.addListener(onTyped);
  }

  @override
  void dispose() {
    typing?.cancel();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  void onTyped() {
    typing?.cancel();
    typing = Timer(typingPause, () => apply(controller.text));
    setState(() {}); // Shows or hides the clear button.
  }

  void apply(String text) {
    typing?.cancel();
    final value = text.trim();
    if (value == applied) return;
    applied = value;
    widget.onSearch(value);
  }

  Future<Iterable<Map<String, dynamic>>> suggestions(
    TextEditingValue value,
  ) async {
    final text = value.text.trim();
    if (text.length < 2) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || controller.text.trim() != text) return const [];
    try {
      final result = await widget.api.get(
        '/ejecutivo/solicitudes/sugerencias',
        {...widget.scope(), 'q': text},
      );
      if (controller.text.trim() != text) return const [];
      final requests = (result['solicitudes'] as List)
          .cast<Map<String, dynamic>>();
      asked = text;
      total = result['total'] as int;
      shownRequests = requests.length;
      return [
        for (final r in requests) {...r, 'kind': 'request'},
        for (final p
            in (result['personas'] as List).cast<Map<String, dynamic>>())
          {...p, 'kind': 'person'},
        if (total > requests.length) {'kind': 'all', 'total': total},
      ];
    } catch (_) {
      // Suggestions are optional; the search itself still works.
      return const [];
    }
  }

  static String shortDate(Object? value) {
    final date = DateTime.tryParse('$value');
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  Widget option(Map<String, dynamic> o, VoidCallback onTap) {
    switch (o['kind']) {
      case 'request':
        return ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined, color: brand),
          title: Text('${o['beneficiario'] ?? o['folio']}'),
          subtitle: Text(
            [
              o['folio'],
              o['tipo_apoyo'],
              shortDate(o['fecha_registro']),
              o['estatus'],
            ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right, color: muted),
          onTap: onTap,
        );
      case 'person':
        return ListTile(
          dense: true,
          leading: Icon(
            o['tipo'] == 'Solicitante'
                ? Icons.record_voice_over_outlined
                : Icons.person_outline,
            color: muted,
          ),
          title: Text(
            'Ver ${o['total'] == 1 ? 'la solicitud' : 'las ${o['total']} solicitudes'} de ${o['nombre']}',
          ),
          subtitle: Text('${o['tipo']}'),
          onTap: onTap,
        );
      default:
        return ListTile(
          dense: true,
          leading: const Icon(Icons.search, color: muted),
          title: Text(
            o['total'] == 1
                ? 'Ver el resultado de «$asked»'
                : 'Ver los ${o['total']} resultados de «$asked»',
          ),
          onTap: onTap,
        );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => RawAutocomplete<Map<String, dynamic>>(
      textEditingController: controller,
      focusNode: focus,
      optionsBuilder: suggestions,
      // A person shows all their requests; a request or "all" keeps the text.
      displayStringForOption: (o) =>
          o['kind'] == 'person' ? '${o['nombre']}' : asked,
      onSelected: (o) {
        if (o['kind'] == 'request') {
          apply(asked);
          widget.onOpen(o['solicitud_id'] as int);
        } else {
          apply(o['kind'] == 'person' ? '${o['nombre']}' : asked);
        }
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        textInputAction: TextInputAction.search,
        onSubmitted: (text) {
          onSubmit();
          apply(text);
        },
        decoration: InputDecoration(
          labelText: 'Buscar solicitud',
          hintText: 'Persona, tipo de apoyo, fecha (dd/mm/aaaa) o folio',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    apply('');
                  },
                ),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 420, maxWidth: box.maxWidth),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final o in options) option(o, () => onSelected(o)),
                if (total > shownRequests)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: Text(
                      'Agrega el tipo de apoyo, la fecha o el folio para afinar.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
