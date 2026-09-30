import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    required this.themeStyle,
    required this.onThemeStyleChanged,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final String themeStyle;
  final Future<void> Function(String) onThemeStyleChanged;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final preferences = widget.snapshot.preferences;
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('preferencesLabel'),
          title: strings.text('preferencesPageTitle'),
          description: strings.text('preferencesPageHint'),
        ),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSectionHeading(title: strings.text('displaySettings')),
              const SizedBox(height: 13),
              DropdownButtonFormField<String>(
                value: preferences.currency,
                decoration: InputDecoration(
                  labelText: strings.text('currency'),
                ),
                items: const ['TOMAN', 'CAD', 'USD', 'EUR', 'GBP', 'AUD', 'NZD']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(growable: false),
                onChanged: _busy ? null : (value) => _update(currency: value),
              ),
              const SizedBox(height: 10),
              Text(
                strings.text('currencyHint'),
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 13),
              DropdownButtonFormField<String>(
                value: preferences.calendar,
                decoration: InputDecoration(
                  labelText: strings.text('displayCalendar'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'gregory',
                    child: Text(strings.text('gregory')),
                  ),
                  DropdownMenuItem(
                    value: 'persian',
                    child: Text(strings.text('persian')),
                  ),
                ],
                onChanged: _busy ? null : (value) => _update(calendar: value),
              ),
              const SizedBox(height: 13),
              DropdownButtonFormField<String>(
                value: widget.themeStyle,
                decoration: InputDecoration(
                  labelText: strings.text('themeStyle'),
                ),
                items: [
                  for (final style in ['classic', 'ocean', 'forest'])
                    DropdownMenuItem(
                      value: style,
                      child: Text(
                        strings.text(
                          'theme${style[0].toUpperCase()}${style.substring(1)}',
                        ),
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null && value != widget.themeStyle) {
                          _changeThemeStyle(value);
                        }
                      },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: preferences.weekStart,
                decoration: InputDecoration(
                  labelText: strings.text('weekStart'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(strings.text('sunday')),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(strings.text('monday')),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(strings.text('saturday')),
                  ),
                ],
                onChanged: _busy ? null : (value) => _update(weekStart: value),
              ),
              const SizedBox(height: 8),
              Text(
                strings.text('dateHint'),
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSectionHeading(title: strings.text('dataLabel')),
              const SizedBox(height: 8),
              Text(
                strings.text('backupHint'),
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 12),
              _actionRow('backup', Icons.file_upload_outlined, _exportBackup),
              _actionRow(
                'restore',
                Icons.file_download_outlined,
                _restoreBackup,
              ),
              _actionRow('recovery', Icons.history_rounded, _exportRecovery),
              const Divider(height: 24),
              _actionRow(
                'reset',
                Icons.restart_alt_rounded,
                _reset,
                danger: true,
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionRow(
    String key,
    IconData icon,
    VoidCallback action, {
    bool danger = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: OutlinedButton.icon(
      onPressed: _busy ? null : action,
      icon: Icon(
        icon,
        color: danger ? context.pouchPalette.danger : context.pouchPalette.goldDeep,
      ),
      label: Text(
        widget.strings.text(key),
        style: TextStyle(color: danger ? context.pouchPalette.danger : context.pouchPalette.ink),
      ),
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    ),
  );

  Future<void> _update({
    String? currency,
    String? calendar,
    int? weekStart,
  }) async {
    await widget.run(
      () => widget.bridge.updatePreferences(
        currency: currency ?? widget.snapshot.preferences.currency,
        language: widget.snapshot.preferences.language,
        calendar: calendar ?? widget.snapshot.preferences.calendar,
        weekStart: weekStart ?? widget.snapshot.preferences.weekStart,
      ),
    );
  }

  Future<void> _changeThemeStyle(String style) async {
    setState(() => _busy = true);
    try {
      await widget.onThemeStyleChanged(style);
    } catch (_) {
      if (mounted) showPouchMessage(context, widget.strings, 'saveFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportBackup() =>
      _saveBackup(() => widget.bridge.exportBackup(), 'pouch-backup.json');

  Future<void> _exportRecovery() => _saveBackup(
    () => widget.bridge.exportRecoveryBackup(),
    'pouch-recovery.json',
  );

  Future<void> _saveBackup(
    Future<String> Function() export,
    String filename,
  ) async {
    setState(() => _busy = true);
    try {
      final contents = await export();
      final saved = await widget.bridge.saveBackup(filename, contents);
      if (!mounted) return;
      showPouchMessage(
        context,
        widget.strings,
        saved ? 'backupSaved' : 'backupCancelled',
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase().contains('recovery')
          ? 'noRecovery'
          : 'backupFailed';
      showPouchMessage(context, widget.strings, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() => _busy = true);
    try {
      final contents = await widget.bridge.pickBackup();
      if (!mounted) return;
      if (contents == null) {
        showPouchMessage(context, widget.strings, 'backupCancelled');
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.text('restore')),
          content: Text(widget.strings.text('restoreConfirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.strings.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.text('restore')),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final restored = await widget.run(
        () => widget.bridge.importBackup(contents),
      );
      if (restored && mounted)
        showPouchMessage(context, widget.strings, 'restored');
    } catch (_) {
      if (mounted) showPouchMessage(context, widget.strings, 'invalidData');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('reset')),
        content: Text(widget.strings.text('resetConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.text('reset')),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final accepted = await widget.run(() => widget.bridge.reset());
    if (accepted && mounted)
      showPouchMessage(context, widget.strings, 'resetDone');
  }
}
