import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../core/pouch_bridge.dart';
import '../core/pouch_models.dart';
import '../core/pouch_theme.dart';
import 'pouch_date_picker.dart';

PouchPeriod? periodForDay(PouchSnapshot snapshot, String date) => snapshot
    .periods
    .where(
      (period) =>
          date.compareTo(period.start) >= 0 && date.compareTo(period.end) <= 0,
    )
    .firstOrNull;

PouchPeriod? selectedPouchPeriod(PouchSnapshot snapshot, String? id) =>
    snapshot.periods.where((period) => period.id == id).firstOrNull ??
    snapshot.currentPeriod ??
    snapshot.periods.lastOrNull;

Future<String> formatBudgetDates(
  PouchBridge bridge,
  PouchPeriod period,
  String calendar,
  AppStrings strings,
) async {
  final dates = await Future.wait([
    formatPouchDate(bridge, period.start, calendar, strings),
    formatPouchDate(bridge, period.end, calendar, strings),
  ]);
  return '${dates[0]} – ${dates[1]}';
}

class PouchPeriodLabel extends StatelessWidget {
  const PouchPeriodLabel({
    required this.bridge,
    required this.period,
    required this.calendar,
    required this.strings,
    this.compact = false,
    super.key,
  });
  final PouchBridge bridge;
  final PouchPeriod period;
  final String calendar;
  final AppStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: formatBudgetDates(bridge, period, calendar, strings),
    builder: (context, result) => Text(
      result.data ?? strings.text('loadingBudgetDates'),
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
    ),
  );
}

class PouchPeriodScope extends InheritedWidget {
  const PouchPeriodScope({
    required this.periodId,
    required this.onChanged,
    required super.child,
    super.key,
  });
  final String? periodId;
  final ValueChanged<String> onChanged;
  static PouchPeriodScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PouchPeriodScope>();
  @override
  bool updateShouldNotify(PouchPeriodScope oldWidget) =>
      oldWidget.periodId != periodId;
}

class PouchPeriodSelector extends StatelessWidget {
  const PouchPeriodSelector({
    required this.periods,
    required this.selectedId,
    required this.strings,
    required this.onChanged,
    required this.bridge,
    required this.calendar,
    this.label,
    super.key,
  });
  final List<PouchPeriod> periods;
  final String? selectedId;
  final AppStrings strings;
  final ValueChanged<String> onChanged;
  final PouchBridge bridge;
  final String calendar;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final selected = periods.where((p) => p.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('period-selector-${selected?.id}'),
          initialValue: selected?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label ?? strings.text('budgetPeriod'),
          ),
          hint: Text(strings.text('choosePeriod')),
          items: [
            for (final period in periods.reversed)
              DropdownMenuItem(
                key: ValueKey('period-choice-${period.id}'),
                value: period.id,
                child: PouchPeriodLabel(
                  bridge: bridge,
                  period: period,
                  calendar: calendar,
                  strings: strings,
                  compact: true,
                ),
              ),
          ],
          onChanged: periods.isEmpty
              ? null
              : (id) {
                  if (id != null) onChanged(id);
                },
        ),
        const SizedBox(height: 8),
        PouchPeriodNotice(strings: strings, period: selected),
        if (selected != null &&
            (MediaQuery.sizeOf(context).width < 600 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3))
          PouchPeriodLabel(
            bridge: bridge,
            period: selected,
            calendar: calendar,
            strings: strings,
          ),
      ],
    );
  }
}

class PouchPeriodNotice extends StatelessWidget {
  const PouchPeriodNotice({
    required this.strings,
    required this.period,
    super.key,
  });
  final AppStrings strings;
  final PouchPeriod? period;
  @override
  Widget build(BuildContext context) => Text(
    period == null
        ? strings.text('choosePeriodHint')
        : strings.text(
            period!.status == 'active' ? 'currentBudget' : 'otherBudget',
          ),
    style: TextStyle(color: context.pouchPalette.muted, height: 1.5),
  );
}
