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
    this.onOpenAbout,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final String themeStyle;
  final VoidCallback? onOpenAbout;
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
    const countries = {
      'iran': 'countryIran',
      'canada': 'countryCanada',
      'united_states': 'countryUnitedStates',
      'united_kingdom': 'countryUnitedKingdom',
      'germany': 'countryGermany',
      'australia': 'countryAustralia',
      'new_zealand': 'countryNewZealand',
      'custom': 'countryCustom',
    };
    final region = PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(title: strings.text('regionalSettings')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('country-${preferences.country}'),
            initialValue: preferences.country,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.text('country')),
            items: [
              for (final item in countries.entries)
                DropdownMenuItem(
                  value: item.key,
                  child: Text(strings.text(item.value)),
                ),
            ],
            onChanged: _busy ? null : (value) => _update(country: value),
          ),
          const SizedBox(height: 8),
          Text(strings.text('countryHint')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('currency-${preferences.currency}'),
            initialValue: preferences.currency,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.text('currency')),
            items: [
              for (final item in [
                'TOMAN',
                'CAD',
                'USD',
                'EUR',
                'GBP',
                'AUD',
                'NZD',
              ])
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: _busy ? null : (value) => _update(currency: value),
          ),
          const SizedBox(height: 8),
          Text(strings.text('currencyHint')),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(strings.text('calendarOptions')),
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('calendar-${preferences.calendar}'),
                initialValue: preferences.calendar,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: strings.text('displayCalendar'),
                ),
                items: [
                  for (final item in ['gregory', 'persian'])
                    DropdownMenuItem(
                      value: item,
                      child: Text(strings.text(item)),
                    ),
                ],
                onChanged: _busy ? null : (value) => _update(calendar: value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: ValueKey('week-${preferences.weekStart}'),
                initialValue: preferences.weekStart,
                isExpanded: true,
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
            ],
          ),
        ],
      ),
    );
    final appearance = PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(title: strings.text('appearanceSettings')),
          const SizedBox(height: 16),
          Text(strings.text('language')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final language in ['en', 'fa'])
                ChoiceChip(
                  label: Text(language == 'fa' ? 'فارسی' : 'English'),
                  selected: preferences.language == language,
                  onSelected: _busy ? null : (_) => _update(language: language),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(strings.text('themeStyle')),
          const SizedBox(height: 8),
          for (final style in ['classic', 'ocean', 'forest'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: PouchPalette.forStyle(style).selection,
                selected: widget.themeStyle == style,
                selectedTileColor: PouchPalette.forStyle(style).selection,
                selectedColor: PouchPalette.forStyle(style).goldDeep,
                leading: CircleAvatar(
                  backgroundColor: PouchPalette.forStyle(style).goldDeep,
                  radius: 12,
                ),
                title: Text(
                  strings.text(
                    'theme${style[0].toUpperCase()}${style.substring(1)}',
                  ),
                ),
                trailing: widget.themeStyle == style
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                onTap: _busy ? null : () => _changeThemeStyle(style),
              ),
            ),
          const SizedBox(height: 12),
          Text(strings.text('dateHint')),
        ],
      ),
    );
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('preferencesLabel'),
          title: strings.text('preferencesPageTitle'),
          description: strings.text('preferencesPageHint'),
        ),
        LayoutBuilder(
          builder: (context, size) => size.maxWidth >= 760
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: appearance),
                    const SizedBox(width: 20),
                    Expanded(child: region),
                  ],
                )
              : Column(
                  children: [appearance, const SizedBox(height: 16), region],
                ),
        ),
        const SizedBox(height: 20),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSectionHeading(title: strings.text('dataLabel')),
              const SizedBox(height: 8),
              Text(strings.text('backupHint')),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _actionRow(
                    'backup',
                    Icons.file_upload_outlined,
                    _exportBackup,
                  ),
                  _actionRow(
                    'restore',
                    Icons.file_download_outlined,
                    _restoreBackup,
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(strings.text('moreOptions')),
                children: [
                  _actionRow(
                    'recovery',
                    Icons.history_rounded,
                    _exportRecovery,
                  ),
                ],
              ),
              const Divider(height: 32),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(strings.text('reset')),
                children: [
                  _actionRow(
                    'reset',
                    Icons.restart_alt_rounded,
                    _reset,
                    danger: true,
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PouchCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(strings.text('navAbout')),
            onTap: widget.onOpenAbout,
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
        color: danger
            ? context.pouchPalette.danger
            : context.pouchPalette.goldDeep,
      ),
      label: Text(
        widget.strings.text(key),
        style: TextStyle(
          color: danger
              ? context.pouchPalette.danger
              : context.pouchPalette.ink,
        ),
      ),
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    ),
  );

  Future<void> _update({
    String? country,
    String? language,
    String? currency,
    String? calendar,
    int? weekStart,
  }) async {
    await widget.run(
      () => widget.bridge.updatePreferences(
        country: country ?? widget.snapshot.preferences.country,
        currency: currency ?? widget.snapshot.preferences.currency,
        language: language ?? widget.snapshot.preferences.language,
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
      if (restored && mounted) {
        showPouchMessage(context, widget.strings, 'restored');
      }
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
    if (accepted && mounted) {
      showPouchMessage(context, widget.strings, 'resetDone');
    }
  }
}
