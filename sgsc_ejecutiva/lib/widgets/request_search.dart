import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/executive_api.dart';

/// Search box of the requests table. Suggests beneficiaries, applicants and
/// registration dates as the person types; the server ignores accents and
/// capitals, so "jose perez" also finds "José Pérez".
class RequestSearchField extends StatefulWidget {
  final ExecutiveApi api;

  /// Current dashboard filters, so suggestions lead to rows in the table.
  final Map<String, Object> Function() scope;
  final String initial;
  final ValueChanged<String> onSearch;
  const RequestSearchField({
    super.key,
    required this.api,
    required this.scope,
    required this.onSearch,
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
  String applied = '';

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
      return (result['items'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      // Suggestions are optional; the search itself still works.
      return const [];
    }
  }

  static IconData icon(String kind) => switch (kind) {
    'Beneficiario' => Icons.person_outline,
    'Solicitante' => Icons.record_voice_over_outlined,
    _ => Icons.event_outlined,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => RawAutocomplete<Map<String, dynamic>>(
      textEditingController: controller,
      focusNode: focus,
      optionsBuilder: suggestions,
      displayStringForOption: (option) => '${option['texto']}',
      onSelected: (option) => apply('${option['texto']}'),
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
          hintText: 'Beneficiario, solicitante o fecha (dd/mm/aaaa)',
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
            constraints: BoxConstraints(maxHeight: 280, maxWidth: box.maxWidth),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    dense: true,
                    leading: Icon(icon('${option['tipo']}'), color: muted),
                    title: Text('${option['texto']}'),
                    subtitle: Text('${option['tipo']}'),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
