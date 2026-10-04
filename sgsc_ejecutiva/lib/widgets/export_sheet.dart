import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'executive_widgets.dart';

const exportFormats = {
  'xlsx': ('Excel', 'Hoja de cálculo (.xlsx) para analizar los datos.'),
  'pdf': ('PDF', 'Documento (.pdf) listo para imprimir o compartir.'),
};

/// Choose a format, see exactly what will be exported, then confirm. The
/// format is a selection (segmented control), the download is a single
/// explicit action, so neither looks "already chosen" by colour alone.
/// Pops the exported format on success.
class ExportSheet extends StatefulWidget {
  final int total;
  final List<String> appliedFilters;
  final Future<String?> Function(String format) onExport;
  const ExportSheet({
    super.key,
    required this.total,
    required this.appliedFilters,
    required this.onExport,
  });
  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  String format = 'xlsx';
  bool busy = false;
  String? error;

  Future<void> download() async {
    setState(() {
      busy = true;
      error = null;
    });
    final failure = await widget.onExport(format);
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context, format);
    } else if (failure.isEmpty) {
      setState(() => busy = false); // cancelled by the person: no error
    } else {
      setState(() {
        busy = false;
        error = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final (name, description) = exportFormats[format]!;
    return PopScope(
      canPop: !busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader('Exportar reporte'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.total == 1
                        ? 'Resumen agregado de 1 solicitud.'
                        : 'Resumen agregado de ${widget.total} solicitudes.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Incluye indicadores, gráficas y definiciones. Sin nombres ni registros individuales.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 6),
                  if (widget.appliedFilters.isEmpty)
                    const Text(
                      'Sin filtros: todas las solicitudes del estado asignado.',
                      style: TextStyle(fontSize: 12, color: muted),
                    )
                  else ...[
                    const Text(
                      'Con los filtros aplicados:',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    for (final line in widget.appliedFilters)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '•  $line',
                          style: const TextStyle(fontSize: 12, color: ink),
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  LabeledField(
                    'Formato',
                    SegmentedButton<String>(
                      style: const ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                      ),
                      segments: [
                        for (final e in exportFormats.entries)
                          ButtonSegment(
                            value: e.key,
                            label: Text(e.value.$1),
                            icon: Icon(
                              e.key == 'pdf'
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.table_chart_outlined,
                            ),
                          ),
                      ],
                      selected: {format},
                      onSelectionChanged: busy
                          ? null
                          : (v) => setState(() => format = v.first),
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Notice(error!, error: true),
                  ],
                ],
              ),
            ),
          ),
          SheetFooter(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : download,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(busy ? 'Generando $name…' : 'Descargar $name'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
