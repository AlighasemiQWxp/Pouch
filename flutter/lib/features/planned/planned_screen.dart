import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';

class PlannedScreen extends StatefulWidget {
  const PlannedScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    required this.undo,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final PouchUndo undo;

  @override
  State<PlannedScreen> createState() => _PlannedScreenState();
}

class _PlannedScreenState extends State<PlannedScreen> {
  String _statusFilter = 'pending';

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final items =
        widget.snapshot.planned
            .where(
              (item) => _statusFilter == 'all' || item.status == _statusFilter,
            )
            .toList()
          ..sort((left, right) => left.date.compareTo(right.date));
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('planningLabel'),
          title: strings.text('plannedPageTitle'),
          description: strings.text('plannedPageHint'),
        ),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.text('yourPlans'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  PouchPrimaryButton(
                    label: strings.text('addPlan'),
                    icon: Icons.add_rounded,
                    onPressed: () => _editPlan(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10),
                    ),
                    items: ['pending', 'paid', 'all']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(strings.text(value)),
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
                  _PlannedTile(
                    item: item,
                    strings: strings,
                    currency: widget.snapshot.preferences.currency,
                    calendar: widget.snapshot.preferences.calendar,
                    weekStart: widget.snapshot.preferences.weekStart,
                    startDate: widget.snapshot.startDate,
                    bridge: widget.bridge,
                    today: widget.today,
                    run: widget.run,
                    onEdit: () => _editPlan(item),
                    onDelete: () => _deletePlan(item),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<PouchGoalForecast>>(
          future: widget.bridge.goalForecast(widget.today),
          builder: (context, snapshot) {
            final goals = snapshot.data ?? const [];
            if (goals.isEmpty) return const SizedBox.shrink();
            return PouchCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PouchSectionHeading(title: strings.text('savingsGoalType')),
                  const SizedBox(height: 6),
                  Text(
                    strings.text('goalAdvanced'),
                    style: TextStyle(
                      color: context.pouchPalette.muted,
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final goal in goals)
                    _GoalForecastTile(
                      goal: goal,
                      item: widget.snapshot.planned.firstWhere(
                        (item) => item.id == goal.id,
                      ),
                      strings: strings,
                      currency: widget.snapshot.preferences.currency,
                      today: widget.today,
                      monthlySavings: widget.snapshot
                          .planAt(widget.today)
                          .savings,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _editPlan([PouchPlannedItem? existing]) async {
    final result = await showDialog<_PlannedValues>(
      context: context,
      builder: (context) => _PlannedDialog(
        bridge: widget.bridge,
        strings: widget.strings,
        today: widget.today,
        firstDate: widget.snapshot.startDate,
        calendar: widget.snapshot.preferences.calendar,
        weekStart: widget.snapshot.preferences.weekStart,
        existing: existing,
      ),
    );
    if (result == null) return;
    await widget.run(
      () => widget.bridge.savePlanned(
        id: existing?.id ?? _newId(),
        description: result.description,
        amount: result.amount,
        category: result.category,
        kind: result.kind,
        date: result.date,
      ),
    );
  }

  Future<void> _deletePlan(PouchPlannedItem item) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('deletePlan')),
        content: Text(item.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.text('delete')),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final deleted = await widget.run(
      () => widget.bridge.removePlanned(item.id),
    );
    if (deleted && mounted) {
      showPouchUndoMessage(context, widget.strings, 'deleted', widget.undo);
    }
  }
}

class _PlannedTile extends StatelessWidget {
  const _PlannedTile({
    required this.item,
    required this.strings,
    required this.currency,
    required this.calendar,
    required this.weekStart,
    required this.startDate,
    required this.bridge,
    required this.today,
    required this.run,
    required this.onEdit,
    required this.onDelete,
  });

  final PouchPlannedItem item;
  final AppStrings strings;
  final String currency;
  final String calendar;
  final int weekStart;
  final String startDate;
  final PouchBridge bridge;
  final String today;
  final PouchMutation run;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final pending = item.status == 'pending';
    final icon = item.kind == 'goal'
        ? Icons.savings_outlined
        : Icons.event_note_outlined;
    final titleAndDate = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.description,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 4,
          children: [
            Text(
              strings.text(
                item.kind == 'goal' ? 'savingsGoalType' : 'plannedExpenseType',
              ),
              style: TextStyle(color: context.pouchPalette.muted, fontSize: 11),
            ),
            PouchDateLabel(
              bridge: bridge,
              strings: strings,
              date: item.date,
              calendar: calendar,
            ),
          ],
        ),
        if (!pending && item.paidDate != null)
          FutureBuilder<String>(
            future: formatPouchDate(bridge, item.paidDate!, calendar, strings),
            builder: (context, value) => Text(
              strings.text('planPaid', {
                'date':
                    value.data ??
                    localizeDigits(item.paidDate!, strings.language),
              }),
              style: TextStyle(color: context.pouchPalette.muted, fontSize: 11),
            ),
          ),
      ],
    );
    final amount = Text(
      formatMoney(item.amount, currency, strings),
      style: TextStyle(fontWeight: FontWeight.w700),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PouchIconButton(
          label: strings.text(
            item.kind == 'goal' ? 'goalPurchased' : 'recordPayment',
          ),
          icon: Icons.check_circle_outline_rounded,
          onPressed: () => _recordPayment(context),
        ),
        PouchIconButton(
          label: strings.text('edit'),
          icon: Icons.edit_outlined,
          onPressed: onEdit,
        ),
        PouchIconButton(
          label: strings.text('delete'),
          icon: Icons.delete_outline_rounded,
          onPressed: onDelete,
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(13, 11, 6, 11),
      decoration: BoxDecoration(
        color: item.kind == 'goal'
            ? context.pouchPalette.surfaceWarm
            : context.pouchPalette.surface,
        border: Border.all(color: context.pouchPalette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconWidget = Icon(icon, color: context.pouchPalette.goldDeep, size: 20);
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 11),
                    Expanded(child: titleAndDate),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [amount, if (pending) actions],
                ),
              ],
            );
          }
          return Row(
            children: [
              iconWidget,
              const SizedBox(width: 11),
              Expanded(child: titleAndDate),
              amount,
              if (pending) actions,
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordPayment(BuildContext context) async {
    final values = await showDialog<_PaymentValues>(
      context: context,
      builder: (context) => _PaymentDialog(
        bridge: bridge,
        strings: strings,
        today: today,
        firstDate: startDate,
        calendar: calendar,
        weekStart: weekStart,
        amount: amountInput(item.amount, language: strings.language),
      ),
    );
    if (values == null) return;
    await run(
      () => bridge.markPlannedPaid(
        planId: item.id,
        purchaseId: _newId(),
        paidDate: values.date,
        amount: values.amount,
      ),
    );
  }
}

class _GoalForecastTile extends StatelessWidget {
  const _GoalForecastTile({
    required this.goal,
    required this.item,
    required this.strings,
    required this.currency,
    required this.today,
    required this.monthlySavings,
  });

  final PouchGoalForecast goal;
  final PouchPlannedItem item;
  final AppStrings strings;
  final String currency;
  final String today;
  final int monthlySavings;

  @override
  Widget build(BuildContext context) {
    final required = goal.requiredMonthly;
    final daysUntil = DateTime.parse('${item.date}T00:00:00Z')
        .difference(DateTime.parse('${today}T00:00:00Z'))
        .inDays;
    var timeRemaining = strings.text('overdueByDays', {
      'days': localizeDigits('${daysUntil.abs()}', strings.language),
    });
    if (daysUntil >= 0) {
      timeRemaining = strings.text('dueInDays', {
        'days': localizeDigits('$daysUntil', strings.language),
      });
    }
    final text = required == null
        ? strings.text('goalNoTime')
        : goal.onTrack
        ? strings.text('goalEnough')
        : strings.text('goalDifference', {
            'amount': formatMoney(goal.difference ?? 0, currency, strings),
          });
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('goalTarget', {
              'amount': formatMoney(item.amount, currency, strings),
            }),
            style: TextStyle(
              color: context.pouchPalette.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            strings.text('goalTimeRemaining', {'time': timeRemaining}),
            style: TextStyle(
              color: context.pouchPalette.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            strings.text('goalCurrentMonthly', {
              'amount': formatMoney(monthlySavings, currency, strings),
            }),
            style: TextStyle(
              color: context.pouchPalette.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          if (required != null) ...[
            const SizedBox(height: 3),
            Text(
              strings.text('goalRequiredMonthly', {
                'amount': formatMoney(required, currency, strings),
              }),
              style: TextStyle(
                color: context.pouchPalette.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  item.description,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${goal.percent}%',
                style: TextStyle(
                  color: context.pouchPalette.goldDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: goal.percent / 100,
              minHeight: 7,
              color: context.pouchPalette.goldBright,
              backgroundColor: context.pouchPalette.border,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: TextStyle(
              color: context.pouchPalette.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          Text(
            strings.text('goalProjection', {
              'percent': localizeDigits('${goal.percent}', strings.language),
            }),
            style: TextStyle(
              color: context.pouchPalette.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          Text(
            strings.text('goalRemaining', {
              'amount': formatMoney(goal.projected, currency, strings),
            }),
            style: TextStyle(
              color: context.pouchPalette.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannedDialog extends StatefulWidget {
  const _PlannedDialog({
    required this.bridge,
    required this.strings,
    required this.today,
    required this.firstDate,
    required this.calendar,
    required this.weekStart,
    this.existing,
  });

  final PouchBridge bridge;
  final AppStrings strings;
  final String today;
  final String firstDate;
  final String calendar;
  final int weekStart;
  final PouchPlannedItem? existing;

  @override
  State<_PlannedDialog> createState() => _PlannedDialogState();
}

class _PlannedDialogState extends State<_PlannedDialog> {
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : amountInput(
            widget.existing!.amount,
            language: widget.strings.language,
          ),
  );
  late String _date = widget.existing?.date ?? widget.today;
  late String _kind = widget.existing?.kind ?? 'expense';
  late String _category = widget.existing?.category ?? 'other';

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.strings.text(widget.existing == null ? 'addPlan' : 'editPlan'),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: InputDecoration(
              labelText: widget.strings.text('plannedType'),
            ),
            items: ['expense', 'goal']
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      widget.strings.text(
                        value == 'goal'
                            ? 'savingsGoalType'
                            : 'plannedExpenseType',
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _kind = value ?? 'expense'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: widget.strings.text('description'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            inputFormatters: [
              PouchMoneyInputFormatter(widget.strings.language),
            ],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.strings.text('amount'),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: InputDecoration(
              labelText: widget.strings.text('category'),
            ),
            items:
                const [
                      'other',
                      'food',
                      'transport',
                      'shopping',
                      'health',
                      'entertainment',
                      'bills',
                    ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(widget.strings.text(value)),
                      ),
                    )
                    .toList(growable: false),
            onChanged: (value) => setState(() => _category = value ?? 'other'),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              widget.strings.text(_kind == 'goal' ? 'targetDate' : 'dueDate'),
            ),
            subtitle: PouchDateLabel(
              bridge: widget.bridge,
              strings: widget.strings,
              date: _date,
              calendar: widget.calendar,
            ),
            trailing: Icon(
              Icons.calendar_month_rounded,
              color: context.pouchPalette.goldDeep,
            ),
            onTap: () async {
              final picked = await showPouchDatePicker(
                context: context,
                bridge: widget.bridge,
                strings: widget.strings,
                initialDate: _date,
                calendar: widget.calendar,
                weekStart: widget.weekStart,
                firstDate: widget.firstDate,
                lastDate: '9998-12-31',
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _PlannedValues(
            _description.text,
            _amount.text,
            _category,
            _kind,
            _date,
          ),
        ),
        child: Text(widget.strings.text('save')),
      ),
    ],
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.bridge,
    required this.strings,
    required this.today,
    required this.firstDate,
    required this.calendar,
    required this.weekStart,
    required this.amount,
  });

  final PouchBridge bridge;
  final AppStrings strings;
  final String today;
  final String firstDate;
  final String calendar;
  final int weekStart;
  final String amount;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.amount);
  late String _date = widget.today;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.text('recordPayment')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _amount,
          inputFormatters: [
            PouchMoneyInputFormatter(widget.strings.language),
          ],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: widget.strings.text('actualAmount'),
          ),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.strings.text('paymentDate')),
          subtitle: PouchDateLabel(
            bridge: widget.bridge,
            strings: widget.strings,
            date: _date,
            calendar: widget.calendar,
          ),
          trailing: const Icon(Icons.calendar_month_rounded),
          onTap: () async {
            final picked = await showPouchDatePicker(
              context: context,
              bridge: widget.bridge,
              strings: widget.strings,
              initialDate: _date,
              calendar: widget.calendar,
              weekStart: widget.weekStart,
              firstDate: widget.firstDate,
              lastDate: widget.today,
            );
            if (picked != null) setState(() => _date = picked);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, _PaymentValues(_date, _amount.text)),
        child: Text(widget.strings.text('confirmPayment')),
      ),
    ],
  );
}

class _PlannedValues {
  const _PlannedValues(
    this.description,
    this.amount,
    this.category,
    this.kind,
    this.date,
  );
  final String description;
  final String amount;
  final String category;
  final String kind;
  final String date;
}

class _PaymentValues {
  const _PaymentValues(this.date, this.amount);
  final String date;
  final String amount;
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
