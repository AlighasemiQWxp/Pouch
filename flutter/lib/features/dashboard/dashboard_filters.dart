import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../widgets/pouch_date_picker.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_period_selector.dart';
import 'dashboard_models.dart';

class DashboardFilters extends StatelessWidget {
  const DashboardFilters({
    required this.selection,
    required this.today,
    required this.snapshot,
    required this.bridge,
    required this.strings,
    required this.onChanged,
    super.key,
  });

  final DashboardSelection selection;
  final String today;
  final PouchSnapshot snapshot;
  final PouchBridge bridge;
  final AppStrings strings;
  final ValueChanged<DashboardSelection> onChanged;

  @override
  Widget build(BuildContext context) => PouchCard(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final controls = [
          SizedBox(
            width: constraints.maxWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('dashboard-range-${selection.mode}'),
              initialValue: selection.mode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.text('dashboardExplore'),
              ),
              items: [
                for (final mode in [
                  'daily',
                  'weekly',
                  'monthly',
                  'yearly',
                  'custom',
                  'period',
                ])
                  DropdownMenuItem(
                    value: mode,
                    enabled: mode != 'period' || snapshot.periods.isNotEmpty,
                    child: Text(
                      strings.text('dashboardFilter_$mode'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (mode) {
                if (mode != null && mode != selection.mode) {
                  onChanged(selection.copyWith(mode: mode));
                }
              },
            ),
          ),
          _dates(context),
        ];
        if (constraints.maxWidth >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 220, child: controls.first),
              const SizedBox(width: 16),
              Expanded(child: controls.last),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [controls.first, const SizedBox(height: 12), controls.last],
        );
      },
    ),
  );

  Widget _dates(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (selection.mode == 'period')
        DropdownButtonFormField<String>(
          key: ValueKey('dashboard-period-${selection.periodId}'),
          initialValue: selection.periodId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: strings.text('budgetPeriod'),
            hintText: strings.text('dashboardChoosePeriod'),
          ),
          items: [
            for (final period in snapshot.periods)
              DropdownMenuItem(
                key: ValueKey('dashboard-period-choice-${period.id}'),
                value: period.id,
                child: PouchPeriodLabel(
                  bridge: bridge,
                  period: period,
                  calendar: snapshot.preferences.calendar,
                  strings: strings,
                  compact: true,
                ),
              ),
          ],
          onChanged: (id) {
            if (id != null && id != selection.periodId) {
              onChanged(selection.copyWith(periodId: id));
            }
          },
        )
      else
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (selection.mode == 'custom') ...[
              _dateButton(
                context,
                'from',
                selection.from ?? selection.anchor,
                (date) => selection.copyWith(from: date),
              ),
              _dateButton(
                context,
                'to',
                selection.through ?? selection.anchor,
                (date) => selection.copyWith(through: date),
              ),
            ] else
              _dateButton(
                context,
                'date',
                selection.anchor,
                (date) => selection.copyWith(anchor: date),
              ),
          ],
        ),
      if (selection.mode == 'period' &&
          (MediaQuery.sizeOf(context).width < 600 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3))
        for (final period in snapshot.periods.where(
          (p) => p.id == selection.periodId,
        ))
          PouchPeriodLabel(
            bridge: bridge,
            period: period,
            calendar: snapshot.preferences.calendar,
            strings: strings,
          ),
      if (selection.mode != 'monthly' || selection.anchor != today)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('dashboard-reset-range'),
            onPressed: () =>
                onChanged(selection.copyWith(mode: 'monthly', anchor: today)),
            icon: const Icon(Icons.today_outlined),
            label: Text(strings.text('dashboardThisMonth')),
          ),
        ),
    ],
  );

  Widget _dateButton(
    BuildContext context,
    String label,
    String date,
    DashboardSelection Function(String) update,
  ) => OutlinedButton.icon(
    key: ValueKey('dashboard-date-$label'),
    icon: const Icon(Icons.calendar_month_outlined),
    label: Wrap(
      spacing: 8,
      children: [
        Text(strings.text(label)),
        PouchDateLabel(
          bridge: bridge,
          strings: strings,
          date: date,
          calendar: snapshot.preferences.calendar,
        ),
      ],
    ),
    onPressed: () async {
      final chosen = await showPouchDatePicker(
        context: context,
        bridge: bridge,
        strings: strings,
        initialDate: date,
        calendar: snapshot.preferences.calendar,
        weekStart: snapshot.preferences.weekStart,
        firstDate: firstPouchRecordDate,
        lastDate: lastPouchRecordDate,
      );
      if (chosen != null && context.mounted) onChanged(update(chosen));
    },
  );
}
