import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_formatters.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';
import '../../widgets/pouch_period_selector.dart';

class PeriodControls extends StatelessWidget {
  const PeriodControls({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.view,
    required this.run,
    required this.select,
    super.key,
  });
  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchPeriodView? view;
  final PouchMutation run;
  final ValueChanged<String> select;
  Widget dates(PouchPeriod period) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      PouchDateLabel(
        bridge: bridge,
        strings: strings,
        date: period.start,
        calendar: snapshot.preferences.calendar,
      ),
      Text(strings.text('dateThrough')),
      PouchDateLabel(
        bridge: bridge,
        strings: strings,
        date: period.end,
        calendar: snapshot.preferences.calendar,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final selected = view?.period ?? snapshot.currentPeriod;
    return PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(
            title: strings.text('budgetPeriod'),
            trailing: TextButton.icon(
              onPressed: () => _save(context),
              icon: const Icon(Icons.add),
              label: Text(strings.text('createPeriod')),
            ),
          ),
          const SizedBox(height: 12),
          PouchPeriodSelector(
            periods: snapshot.periods,
            selectedId: selected?.id,
            strings: strings,
            onChanged: (id) => select(
              snapshot.periods.firstWhere((period) => period.id == id).start,
            ),
          ),
          const SizedBox(height: 12),
          if (snapshot.periods.isEmpty) Text(strings.text('firstPeriodHint')),
          if (selected != null) ...[
            dates(selected),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(strings.text('period_${selected.status}'))),
                if (today.compareTo(selected.start) >= 0 &&
                    today.compareTo(selected.end) <= 0)
                  Text(
                    strings.text('daysToLast', {
                      'days': localizeDigits(
                        '${DateTime.parse(selected.end).difference(DateTime.parse(today)).inDays + 1}',
                        strings.language,
                      ),
                    }),
                  ),
                TextButton.icon(
                  key: const ValueKey('edit-period'),
                  onPressed: () => _save(context, selected),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(strings.text('editPeriod')),
                ),
                TextButton.icon(
                  key: const ValueKey('delete-period'),
                  onPressed: () => _delete(context, selected),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(strings.text('deletePeriod')),
                ),
              ],
            ),
          ],
          if (snapshot.periods.isNotEmpty)
            ExpansionTile(
              key: const ValueKey('period-history'),
              tilePadding: EdgeInsets.zero,
              title: Text(strings.text('periodHistory')),
              children: [
                for (final period in snapshot.periods.reversed)
                  ListTile(
                    key: ValueKey('select-${period.id}'),
                    contentPadding: EdgeInsets.zero,
                    selected: period.id == selected?.id,
                    title: Text(period.displayName),
                    subtitle: dates(period),
                    trailing: period.id == selected?.id
                        ? const Icon(Icons.check_circle_outline)
                        : null,
                    onTap: () => select(period.start),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, PouchPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('deletePeriod')),
        content: Text(
          strings.text('deletePeriodConfirmation', {
            'period': period.displayName,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-period'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.text('deletePeriod')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await run(() => bridge.removePeriod(period.id));
    if (!deleted) return;
    final remaining = snapshot.periods
        .where((item) => item.id != period.id)
        .toList();
    final fallback =
        remaining
            .where(
              (item) =>
                  today.compareTo(item.start) >= 0 &&
                  today.compareTo(item.end) <= 0,
            )
            .firstOrNull ??
        remaining.lastOrNull;
    if (fallback != null) select(fallback.start);
  }

  Future<void> _save(BuildContext context, [PouchPeriod? period]) async {
    final choice = await showPeriodDialog(
      context: context,
      bridge: bridge,
      snapshot: snapshot,
      strings: strings,
      start: period?.start ?? today,
      period: period,
    );
    if (choice == null) return;
    final saved = await run(
      () => bridge.savePeriod(
        id: period?.id,
        start: choice.start,
        kind: choice.kind,
        customDays: choice.days,
        through: choice.through,
      ),
    );
    if (saved) select(choice.start);
  }
}

class PeriodChoice {
  const PeriodChoice(this.start, this.kind, this.days, this.through);
  final String start, kind;
  final int days;
  final String? through;
}

Future<PeriodChoice?> showPeriodDialog({
  required BuildContext context,
  required PouchBridge bridge,
  required PouchSnapshot snapshot,
  required AppStrings strings,
  required String start,
  PouchPeriod? period,
  bool fixedStart = false,
}) => showDialog<PeriodChoice>(
  context: context,
  builder: (_) => _PeriodDialog(
    bridge: bridge,
    snapshot: snapshot,
    strings: strings,
    initialStart: start,
    period: period,
    fixedStart: fixedStart,
  ),
);

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.initialStart,
    required this.period,
    required this.fixedStart,
  });
  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String initialStart;
  final PouchPeriod? period;
  final bool fixedStart;
  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late String start = widget.initialStart;
  late String through = widget.period?.end ?? start;
  late String kind = widget.period?.recurrence ?? 'monthly';
  late bool customEnd = widget.period != null;
  String? error;
  late final days = TextEditingController(
    text:
        '${widget.period?.customDays == 0 ? 7 : widget.period?.customDays ?? 7}',
  );
  @override
  void dispose() {
    days.dispose();
    super.dispose();
  }

  Future<void> pick(bool first) async {
    final result = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: first ? start : through,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: first ? firstPouchRecordDate : start,
      lastDate: lastPouchRecordDate,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (first) {
        start = result;
        if (through.compareTo(start) < 0) through = start;
      } else {
        through = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.strings.text(
        widget.period == null ? 'createPeriod' : 'editPeriod',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.strings.text('planningHorizonHint')),
            const SizedBox(height: 16),
            Text(widget.strings.text('periodStart')),
            TextButton(
              onPressed: widget.fixedStart ? null : () => pick(true),
              child: PouchDateLabel(
                bridge: widget.bridge,
                strings: widget.strings,
                date: start,
                calendar: widget.snapshot.preferences.calendar,
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.strings.text('moneyShouldLast')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in [
                  'weekly',
                  'biweekly',
                  'monthly',
                  'custom',
                  'once',
                ])
                  ChoiceChip(
                    label: Text(
                      widget.strings.text(
                        value == 'once' ? 'chooseEndDate' : 'schedule_$value',
                      ),
                    ),
                    selected: (customEnd ? 'once' : kind) == value,
                    onSelected: (_) => setState(() {
                      kind = value;
                      customEnd = value == 'once';
                      error = null;
                    }),
                  ),
              ],
            ),
            if (kind == 'custom' && !customEnd)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.strings.text('intervalDays'),
                  ),
                ),
              ),
            if (kind == 'once' || customEnd)
              TextButton(
                onPressed: () => pick(false),
                child: Column(
                  children: [
                    Text(widget.strings.text('lastBudgetDay')),
                    PouchDateLabel(
                      bridge: widget.bridge,
                      strings: widget.strings,
                      date: through,
                      calendar: widget.snapshot.preferences.calendar,
                    ),
                  ],
                ),
              ),
            if (error != null) PouchInlineError(widget.strings.text(error!)),
            if (widget.period?.status == 'closed')
              Text(widget.strings.text('closedPeriodEditHint')),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
      FilledButton(
        onPressed: () {
          var text = days.text;
          for (var i = 0; i < 10; i++) {
            text = text
                .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i')
                .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i');
          }
          final count = int.tryParse(text) ?? 0;
          if (kind == 'custom' && !customEnd && count <= 0) {
            setState(() => error = 'positivePeriodDays');
            return;
          }
          if ((kind == 'once' || customEnd) && through.compareTo(start) < 0) {
            setState(() => error = 'invalidPeriod');
            return;
          }
          Navigator.pop(
            context,
            PeriodChoice(
              start,
              kind,
              int.tryParse(text) ?? 0,
              kind == 'once' || customEnd ? through : null,
            ),
          );
        },
        child: Text(widget.strings.text('saveChanges')),
      ),
    ],
  );
}
