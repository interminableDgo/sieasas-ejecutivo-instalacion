import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

class ExecutiveCard extends StatelessWidget {
  final String title;
  final String? source;
  final Widget child;
  const ExecutiveCard({
    super.key,
    required this.title,
    required this.child,
    this.source,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
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
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (source != null)
              IconButton(
                tooltip: 'Cómo se calcula',
                icon: const Icon(Icons.info_outline, size: 18, color: muted),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(title),
                    content: Text(source!),
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
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
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
