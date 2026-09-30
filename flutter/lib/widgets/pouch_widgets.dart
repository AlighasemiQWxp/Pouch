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
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
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
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            color: context.pouchPalette.gold,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          title,
          style: TextStyle(
            color: context.pouchPalette.ink,
            fontFamily: 'serif',
            fontSize: 38,
            height: 1.12,
            fontWeight: FontWeight.w500,
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
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: context.pouchPalette.ink, fontWeight: FontWeight.w700),
        ),
      ),
      if (trailing != null) trailing!,
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
