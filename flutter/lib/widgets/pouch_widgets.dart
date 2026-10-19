import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../core/pouch_theme.dart';

typedef PouchUndo = Future<void> Function();

class PouchPage extends StatelessWidget {
  const PouchPage({required this.children, this.controller, super.key});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
      8,
      MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
      32,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class PouchIntro extends StatelessWidget {
  const PouchIntro({
    required this.eyebrow,
    required this.title,
    required this.description,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.pouchPalette.ink,
            fontSize: 26,
            height: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          description,
          style: TextStyle(
            color: context.pouchPalette.muted,
            fontSize: 14,
            height: 1.65,
          ),
        ),
      ],
    ),
  );
}

class PouchCard extends StatelessWidget {
  const PouchCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(padding: padding, child: child),
  );
}

class PouchSectionHeading extends StatelessWidget {
  const PouchSectionHeading({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.pouchPalette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class PouchPrimaryButton extends StatelessWidget {
  const PouchPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon ?? Icons.check_rounded),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: context.pouchPalette.goldDeep,
      foregroundColor: context.pouchPalette.surface,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  );
}

class PouchIconButton extends StatelessWidget {
  const PouchIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, color: context.pouchPalette.goldDeep),
    ),
  );
}

class PouchInlineError extends StatelessWidget {
  const PouchInlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(
      color: context.pouchPalette.danger,
      fontSize: 13,
      height: 1.5,
    ),
  );
}

void showPouchMessage(BuildContext context, AppStrings strings, String key) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(strings.text(key))));
}

void showPouchUndoMessage(
  BuildContext context,
  AppStrings strings,
  String key,
  PouchUndo onUndo,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(strings.text(key)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: strings.text('undo'),
          onPressed: () {
            onUndo();
          },
        ),
      ),
    );
}

class PouchEmptyState extends StatelessWidget {
  const PouchEmptyState({
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.account_balance_wallet_outlined,
    super.key,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => PouchCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.pouchPalette.goldDeep),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class PouchStat extends StatelessWidget {
  const PouchStat({
    required this.label,
    required this.value,
    this.emphasized = false,
    super.key,
  });
  final String label, value;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: emphasized
          ? context.pouchPalette.selection
          : context.pouchPalette.cream,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.pouchPalette.muted)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 26 : 20,
            fontWeight: FontWeight.w700,
            color: context.pouchPalette.ink,
          ),
        ),
      ],
    ),
  );
}

class PouchStatGrid extends StatelessWidget {
  const PouchStatGrid({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class PouchSummaryRow extends StatelessWidget {
  const PouchSummaryRow({required this.label, required this.value, super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, size) {
            if (size.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: context.pouchPalette.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: context.pouchPalette.muted),
                  ),
                ),
                const SizedBox(width: 20),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
