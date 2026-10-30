import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../services/image_clipboard.dart';

class ExecutiveCard extends StatefulWidget {
  final String title;
  final String? source;
  final Widget child;

  /// Shows a button that copies the card (title and chart) as an image.
  final bool copyable;
  const ExecutiveCard({
    super.key,
    required this.title,
    required this.child,
    this.source,
    this.copyable = false,
  });

  @override
  State<ExecutiveCard> createState() => _ExecutiveCardState();
}

class _ExecutiveCardState extends State<ExecutiveCard> {
  final capture = GlobalKey();
  bool capturing = false;

  /// Renders the card without its buttons, on a white background so the
  /// pasted image has no transparent corners.
  Future<Uint8List> image() async {
    setState(() => capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      return data!.buffer.asUint8List();
    } finally {
      if (mounted) setState(() => capturing = false);
    }
  }

  Future<void> copy() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    // The copy starts inside the click so the browser allows the clipboard.
    final png = image();
    var message = 'Gráfica copiada al portapapeles.';
    try {
      if (!await copyPngToClipboard(png)) {
        final name =
            'SIESAS-${widget.title.replaceAll(RegExp(r'[^\wÁÉÍÓÚÑáéíóúñ]+'), '-')}.png';
        final file = XFile.fromData(
          await png,
          name: name,
          mimeType: 'image/png',
        );
        if (kIsWeb) {
          await file.saveTo(name);
          message = 'Tu navegador no permite copiar imágenes. Se descargó la gráfica.';
        } else {
          await SharePlus.instance.share(
            ShareParams(
              files: [file],
              fileNameOverrides: [name],
              sharePositionOrigin: box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
            ),
          );
          return;
        }
      }
    } catch (_) {
      message = 'No se pudo copiar la gráfica. Intenta de nuevo.';
    }
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: RepaintBoundary(
      key: capture,
      child: _CardCapture(
        capturing: capturing,
        child: ColoredBox(
          color: capturing ? Colors.white : Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F1B2A33),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    CopyExclude(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.copyable)
                            IconButton(
                              tooltip: 'Copiar imagen de la gráfica',
                              icon: const Icon(
                                Icons.copy_all_outlined,
                                size: 18,
                                color: muted,
                              ),
                              onPressed: capturing ? null : copy,
                            ),
                          if (widget.source != null)
                            IconButton(
                              tooltip: 'Cómo se calcula',
                              icon: const Icon(
                                Icons.info_outline,
                                size: 18,
                                color: muted,
                              ),
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text(widget.title),
                                  content: Text(widget.source!),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Entendido'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CardCapture extends InheritedWidget {
  final bool capturing;
  const _CardCapture({required this.capturing, required super.child});

  @override
  bool updateShouldNotify(_CardCapture old) => old.capturing != capturing;
}

/// Leaves controls (view selectors, "Ver todos", buttons) out of the image
/// copied from an [ExecutiveCard]; only the title and the data remain.
class CopyExclude extends StatelessWidget {
  final Widget child;
  const CopyExclude({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardCapture>()?.capturing ??
          false
      ? const SizedBox.shrink()
      : child;
}

class Notice extends StatelessWidget {
  final String message;
  final bool error;
  const Notice(this.message, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFF8E7E5) : blueTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: error ? const Color(0xFFC6483F) : ink,
        ),
      ),
    ),
  );
}

/// Compact status glyph for the request table. The SSNL schema has no closure
/// timestamp, so completed requests deliberately show no invented duration.
class StatusDaysIcon extends StatelessWidget {
  final String status;
  final Object? registeredAt;

  const StatusDaysIcon({
    super.key,
    required this.status,
    required this.registeredAt,
  });

  String get normalizedStatus => status.trim().toLowerCase();
  bool get resolved => normalizedStatus.startsWith('resuelto');
  bool get closed =>
      resolved ||
      normalizedStatus.contains('cerrado') ||
      normalizedStatus.contains('cancelado') ||
      normalizedStatus == 'no es competencia';
  bool get pending =>
      normalizedStatus.contains('inicio') ||
      normalizedStatus.contains('pendiente');

  int? get daysSinceRegistration {
    final parsed = DateTime.tryParse('$registeredAt');
    if (parsed == null) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    final elapsed = today
        .difference(DateUtils.dateOnly(parsed.toLocal()))
        .inDays;
    return elapsed < 0 ? 0 : elapsed;
  }

  @override
  Widget build(BuildContext context) {
    final days = daysSinceRegistration;
    const blue = Color(0xFF12A5E5);
    const yellow = Color(0xFFF4B400);
    const green = Color(0xFF27834A);
    const red = Color(0xFFD32F2F);
    final marker = days?.toString() ?? '?';
    final description = closed
        ? resolved
              ? days == null
                    ? '$status · días desde el registro no disponibles; la base no guarda la fecha de cierre para calcular cuánto tardó en resolverse'
                    : '$status · $days días desde el registro hasta hoy; no es el tiempo que tardó en resolverse, porque la base no guarda la fecha de cierre'
              : '$status · cerrada; duración no disponible porque falta la fecha de cierre'
        : days == null
        ? '$status · días desde el registro no disponibles'
        : '$status · $days días desde el registro';
    return Tooltip(
      message: description,
      child: Semantics(
        label: description,
        child: SizedBox.square(
          dimension: 36,
          child: Center(
            child: resolved
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          marker,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  )
                : closed
                ? const Icon(Icons.cancel_rounded, color: red, size: 30)
                : Stack(
                    alignment: Alignment.center,
                    children: pending
                        ? [
                            CustomPaint(
                              size: const Size(36, 36),
                              painter: _DaysTrianglePainter(yellow),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: SizedBox(
                                width: 28,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    marker,
                                    style: const TextStyle(
                                      color: ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ]
                        : [
                            const Icon(Icons.circle, color: blue, size: 30),
                            SizedBox(
                              width: 26,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  marker,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DaysTrianglePainter extends CustomPainter {
  final Color color;
  const _DaysTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final triangle = Path()
      ..moveTo(size.width / 2, 2)
      ..lineTo(size.width - 1, size.height - 2)
      ..lineTo(1, size.height - 2)
      ..close();
    canvas.drawPath(triangle, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DaysTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const LabeledField(this.label, this.child, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

/// Wizard position: a large step number, the section and title, and one
/// segment per step (completed, current, pending). Ink on orange keeps the
/// number legible (≈ 6.8:1); color is never the only cue, since completed
/// segments also show a check.
class StepProgress extends StatelessWidget {
  final int current, total;
  final String section, title;
  const StepProgress({
    super.key,
    required this.current,
    required this.total,
    required this.section,
    required this.title,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: 'Paso $current de $total: $section, $title',
    child: ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: blueTint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: salud.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: brand,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$current',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PASO $current DE $total · ${section.toUpperCase()}',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          color: ink,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 1; i <= total; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < current
                            ? salud
                            : i == current
                            ? brand
                            : Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: i <= current ? Colors.transparent : border,
                        ),
                      ),
                      child: i < current
                          ? const Icon(Icons.check, size: 13, color: ink)
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const PageHeading(this.title, {super.key, required this.onBack});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Volver',
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    ),
  );
}

/// Filters, pickers and exports open as a white bottom sheet: the phone
/// convention, reachable with the thumb and never wider or taller than the
/// screen. Its content scrolls inside; the page behind does not move.
Future<T?> showPhoneSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  double heightFactor = 0.9,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * heightFactor,
  ),
  builder: builder,
);

/// Title row shared by sheets: title, optional action and a close button
/// (drag handles are not obvious on desktop, Escape is not on touch).
class SheetHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SheetHeader(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

/// Action area pinned to the bottom of a sheet, always in view.
class SheetFooter extends StatelessWidget {
  final List<Widget> children;
  const SheetFooter({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: border)),
    ),
    // Clear of the iPhone home indicator.
    child: SafeArea(
      top: false,
      left: false,
      right: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

bool isCupertino(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

/// Native-looking confirmation on each platform: a Cupertino alert on iOS,
/// a Material dialog on Android. Resolves to true only on [action].
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool destructive = false,
}) async {
  Widget button(BuildContext c, String label, bool value) => isCupertino(c)
      ? CupertinoDialogAction(
          isDefaultAction: !value,
          isDestructiveAction: value && destructive,
          onPressed: () => Navigator.pop(c, value),
          child: Text(label),
        )
      : TextButton(
          onPressed: () => Navigator.pop(c, value),
          child: Text(label),
        );
  return await showAdaptiveDialog<bool>(
        context: context,
        builder: (c) => AlertDialog.adaptive(
          title: Text(title),
          content: Text(body),
          actions: [button(c, 'Cancelar', false), button(c, action, true)],
        ),
      ) ==
      true;
}
