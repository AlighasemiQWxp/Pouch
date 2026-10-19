import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../core/pouch_models.dart';
import '../core/pouch_theme.dart';

PouchPeriod? selectedPouchPeriod(PouchSnapshot snapshot, String? id) =>
    snapshot.periods.where((period) => period.id == id).firstOrNull ??
    snapshot.currentPeriod ??
    snapshot.periods.lastOrNull;

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
    this.label,
    super.key,
  });

  final List<PouchPeriod> periods;
  final String? selectedId;
  final AppStrings strings;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final selected = periods
        .where((period) => period.id == selectedId)
        .firstOrNull;
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
                child: Text(
                  period.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        : strings.text('periodCalculationHint', {
            'period': period!.displayName,
          }),
    style: TextStyle(color: context.pouchPalette.muted, height: 1.5),
  );
}
