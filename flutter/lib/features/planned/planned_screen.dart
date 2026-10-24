import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_period_selector.dart';
import '../budget_plan/essential_expenses.dart';
import 'planned_item_widgets.dart';

class PlannedScreen extends StatefulWidget {
  const PlannedScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    required this.undo,
    this.kind = 'expense',
    this.onForecast,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final PouchUndo undo;
  final String kind;
  final ValueChanged<PouchPlannedItem>? onForecast;

  @override
  State<PlannedScreen> createState() => _PlannedScreenState();
}

class _PlannedScreenState extends State<PlannedScreen> {
  String _statusFilter = 'pending';
  String? _periodId;
  late String _kind = widget.kind;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final selected = selectedPouchPeriod(
      widget.snapshot,
      PouchPeriodScope.maybeOf(context)?.periodId ?? _periodId,
    );
    final items =
        widget.snapshot.planned
            .where(
              (item) =>
                  item.kind == _kind &&
                  (_kind == 'goal' ||
                      item.periodId == null ||
                      item.periodId == selected?.id) &&
                  _matchesStatus(item),
            )
            .toList()
          ..sort((left, right) => left.date.compareTo(right.date));
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('planningLabel'),
          title: strings.text('plansTitle'),
          description: strings.text('plansHint'),
        ),
        if (_kind == 'expense')
          PouchPeriodSelector(
            bridge: widget.bridge,
            calendar: widget.snapshot.preferences.calendar,
            periods: widget.snapshot.periods,
            selectedId: selected?.id,
            strings: strings,
            onChanged: (id) {
              setState(() => _periodId = id);
              PouchPeriodScope.maybeOf(context)?.onChanged(id);
            },
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final kind in ['expense', 'goal'])
              ChoiceChip(
                label: Text(
                  strings.text(kind == 'goal' ? 'navSavings' : 'navPlanned'),
                ),
                selected: _kind == kind,
                onSelected: (_) => setState(() {
                  _kind = kind;
                  _statusFilter = 'pending';
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    strings.text(_kind == 'goal' ? 'yourGoals' : 'yourPlans'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  PouchPrimaryButton(
                    label: strings.text(
                      _kind == 'goal' ? 'addGoal' : 'addPlannedExpense',
                    ),
                    icon: Icons.add_rounded,
                    onPressed: () => _editPlan(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('plan-status-$_kind'),
                    initialValue: _statusFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10),
                    ),
                    items:
                        (_kind == 'goal'
                                ? ['pending', 'paid', 'all']
                                : [
                                    'pending',
                                    'dueSoon',
                                    'overdue',
                                    'paid',
                                    'all',
                                  ])
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  strings.text(_statusLabel(value)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => _statusFilter = value ?? 'pending'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    strings.text('noPlans'),
                    style: TextStyle(
                      color: context.pouchPalette.muted,
                      height: 1.6,
                    ),
                  ),
                )
              else
                for (final item in items)
                  PlannedItemTile(
                    item: item,
                    strings: strings,
                    currency: widget.snapshot.preferences.currency,
                    calendar: widget.snapshot.preferences.calendar,
                    weekStart: widget.snapshot.preferences.weekStart,
                    startDate: widget.snapshot.startDate,
                    bridge: widget.bridge,
                    today: widget.today,
                    run: widget.run,
                    onForecast: widget.onForecast == null
                        ? null
                        : () => widget.onForecast!(item),
                    onEdit: () => _editPlan(item),
                    onDelete: () => _deletePlan(item),
                  ),
            ],
          ),
        ),
        if (_kind == 'expense' &&
            widget.snapshot.essentials.any((item) => item.until == null)) ...[
          const SizedBox(height: 20),
          EssentialExpenses(
            bridge: widget.bridge,
            snapshot: widget.snapshot,
            strings: strings,
            today: widget.today,
            run: widget.run,
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  bool _matchesStatus(PouchPlannedItem item) {
    if (_statusFilter == 'all') return true;
    if (_statusFilter == 'overdue') {
      return item.status == 'pending' && item.date.compareTo(widget.today) < 0;
    }
    if (_statusFilter == 'dueSoon') {
      final through = DateTime.parse('${widget.today}T00:00:00Z')
          .add(const Duration(days: 7))
          .toIso8601String()
          .substring(0, 10);
      return item.status == 'pending' &&
          item.date.compareTo(widget.today) >= 0 &&
          item.date.compareTo(through) <= 0;
    }
    return item.status == _statusFilter;
  }

  String _statusLabel(String status) {
    if (status == 'all') return 'all';
    if (_kind == 'goal') {
      return status == 'paid' ? 'goalPurchased' : 'goalSaving';
    }
    return switch (status) {
      'paid' => 'paid',
      'overdue' => 'billOverdue',
      'dueSoon' => 'billDueSoon',
      _ => 'billUnpaid',
    };
  }

  Future<void> _editPlan([PouchPlannedItem? existing]) => editPlannedItem(
    context: context,
    bridge: widget.bridge,
    snapshot: widget.snapshot,
    strings: widget.strings,
    today: widget.today,
    run: widget.run,
    initialPeriodId: selectedPouchPeriod(
      widget.snapshot,
      PouchPeriodScope.maybeOf(context)?.periodId ?? _periodId,
    )?.id,
    kind: _kind,
    existing: existing,
  );

  Future<void> _deletePlan(PouchPlannedItem item) => deletePlannedItem(
    context: context,
    bridge: widget.bridge,
    strings: widget.strings,
    run: widget.run,
    undo: widget.undo,
    item: item,
  );
}
