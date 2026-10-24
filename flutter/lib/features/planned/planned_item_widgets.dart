import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_motion.dart';
import '../../widgets/pouch_period_selector.dart';
import '../../widgets/pouch_date_picker.dart';

Future<void> editPlannedItem({
  required BuildContext context,
  required PouchBridge bridge,
  required PouchSnapshot snapshot,
  required AppStrings strings,
  required String today,
  required PouchMutation run,
  String kind = 'expense',
  String? initialPeriodId,
  String? initialDate,
  PouchPlannedItem? existing,
  PouchRequiredExpense? recurringExpense,
}) async {
  final periodId =
      existing?.periodId ??
      initialPeriodId ??
      periodForDay(snapshot, initialDate ?? today)?.id ??
      snapshot.currentPeriod?.id;
  final id = existing?.id ?? recurringExpense?.id ?? _newId();
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PlannedDialog(
      bridge: bridge,
      strings: strings,
      today: today,
      firstDate: firstPouchRecordDate,
      calendar: snapshot.preferences.calendar,
      weekStart: snapshot.preferences.weekStart,
      existing: existing,
      recurringExpense: recurringExpense,
      initialKind: kind,
      initialDate: initialDate,
      periods: snapshot.periods,
      initialPeriodId: periodId,
      onSave: (result) => run(() {
        if (result.repeat != 'once' || recurringExpense != null) {
          return bridge.saveEssentialExpense(
            id: id,
            name: result.description,
            amount: result.amount,
            date: result.date,
            kind: result.repeat,
            customDays: result.customDays,
          );
        }
        return bridge.savePlanned(
          id: id,
          description: result.description,
          amount: result.amount,
          category: result.category,
          kind: result.kind,
          date: result.date,
          periodId: result.periodId,
        );
      }),
    ),
  );
  if (saved == true &&
      context.mounted &&
      existing == null &&
      recurringExpense == null) {
    PouchMotion.celebrate(context);
  }
}

Future<void> deletePlannedItem({
  required BuildContext context,
  required PouchBridge bridge,
  required AppStrings strings,
  required PouchMutation run,
  required PouchUndo undo,
  required PouchPlannedItem item,
}) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.text('deletePlan')),
      content: Text(item.description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.text('delete')),
        ),
      ],
    ),
  );
  if (approved != true || !context.mounted) return;
  final deleted = await run(() => bridge.removePlanned(item.id));
  if (deleted && context.mounted) {
    showPouchUndoMessage(context, strings, 'deleted', undo);
  }
}

class PlannedItemTile extends StatelessWidget {
  const PlannedItemTile({
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
    this.working = false,
    this.onForecast,
    super.key,
  });

  final bool working;
  final PouchPlannedItem item;
  final AppStrings strings;
  final String currency;
  final String calendar;
  final int weekStart;
  final String startDate;
  final PouchBridge bridge;
  final String today;
  final PouchMutation run;
  final VoidCallback? onForecast;
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
        Text(item.description, style: TextStyle(fontWeight: FontWeight.w700)),
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
        if (pending)
          Text(
            strings.text(
              item.kind == 'goal'
                  ? 'goalSaving'
                  : (item.date.compareTo(today) < 0
                        ? 'billOverdue'
                        : (item.date.compareTo(
                                    DateTime.parse('${today}T00:00:00Z')
                                        .add(const Duration(days: 7))
                                        .toIso8601String()
                                        .substring(0, 10),
                                  ) <=
                                  0
                              ? 'billDueSoon'
                              : 'billUpcoming')),
            ),
            style: TextStyle(color: context.pouchPalette.goldDeep),
          ),
        if (pending && item.kind == 'goal')
          FutureBuilder<PouchFinancialForecast>(
            future: bridge.financialForecast(
              today,
              item.id,
              periodId: item.periodId,
            ),
            builder: (context, value) {
              if (value.connectionState != ConnectionState.done ||
                  !value.hasData) {
                return const SizedBox.shrink();
              }
              final allocated = value.data!.allocated;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.text(
                      allocated >= item.amount ? 'goalReady' : 'goalProgress',
                      {
                        'amount': formatMoney(allocated, currency, strings),
                        'target': formatMoney(item.amount, currency, strings),
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: item.amount <= 0
                        ? 0
                        : (allocated / item.amount).clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.text('goalPurchaseHint'),
                    style: TextStyle(
                      color: context.pouchPalette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
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
    final actions = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          key: ValueKey('pay-${item.id}'),
          onPressed: working ? null : () => _recordPayment(context),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(
            strings.text(
              item.kind == 'goal' ? 'goalRecordPurchase' : 'recordPayment',
            ),
          ),
        ),
        if (item.kind == 'goal' && onForecast != null)
          TextButton.icon(
            key: ValueKey('goal-forecast-${item.id}'),
            onPressed: onForecast,
            icon: const Icon(Icons.insights_outlined),
            label: Text(strings.text('goalForecast')),
          ),
        if (item.essentialId == null)
          PopupMenuButton<String>(
            enabled: !working,
            tooltip: strings.text('more'),
            onSelected: (action) {
              if (action == 'edit') {
                onEdit();
              } else {
                onDelete();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(strings.text('edit'))),
              PopupMenuItem(
                value: 'delete',
                child: Text(strings.text('delete')),
              ),
            ],
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
          final iconWidget = Icon(
            icon,
            color: context.pouchPalette.goldDeep,
            size: 20,
          );
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [amount, if (pending) actions],
              ),
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
    if (values == null || !context.mounted) return;
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

class _PlannedDialog extends StatefulWidget {
  const _PlannedDialog({
    required this.bridge,
    required this.strings,
    required this.today,
    required this.firstDate,
    required this.calendar,
    required this.weekStart,
    this.existing,
    this.recurringExpense,
    required this.onSave,
    this.initialKind = 'expense',
    this.initialDate,
    required this.periods,
    required this.initialPeriodId,
  });

  final PouchBridge bridge;
  final AppStrings strings;
  final String today;
  final String firstDate;
  final String calendar;
  final int weekStart;
  final PouchPlannedItem? existing;
  final PouchRequiredExpense? recurringExpense;
  final Future<bool> Function(_PlannedValues values) onSave;
  final String initialKind;
  final String? initialDate;
  final List<PouchPeriod> periods;
  final String? initialPeriodId;

  @override
  State<_PlannedDialog> createState() => _PlannedDialogState();
}

class _PlannedDialogState extends State<_PlannedDialog> {
  late final _description = TextEditingController(
    text: widget.existing?.description ?? widget.recurringExpense?.name ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.existing == null && widget.recurringExpense == null
        ? ''
        : amountInput(
            widget.existing?.amount ?? widget.recurringExpense!.amount,
            language: widget.strings.language,
          ),
  );
  late String _date =
      widget.existing?.date ??
      widget.recurringExpense?.date ??
      widget.initialDate ??
      widget.today;
  late final String _kind = widget.existing?.kind ?? widget.initialKind;
  late String _category = widget.existing?.category ?? 'other';
  bool _missingFields = false;
  late String? _periodId = widget.initialPeriodId;
  late String _repeat = widget.recurringExpense?.recurrence ?? 'once';
  late final _days = TextEditingController(
    text: '${widget.recurringExpense?.customDays ?? 7}',
  );
  bool _saving = false;
  String? _saveError;

  Future<void> _save() async {
    if (_saving) return;
    final interval = int.tryParse(localizedInteger(_days.text)) ?? 0;
    if (_description.text.trim().isEmpty ||
        (parseMoneyEntry(_amount.text) ?? 0) <= 0 ||
        (_repeat == 'custom' && interval <= 0)) {
      setState(() => _missingFields = true);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    var accepted = false;
    try {
      accepted = await widget.onSave(
        _PlannedValues(
          _description.text.trim(),
          _amount.text.trim(),
          _category,
          _kind,
          _date,
          _periodId,
          _repeat,
          interval,
        ),
      );
    } catch (_) {
      accepted = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!accepted) _saveError = 'entrySaveFailed';
    });
    if (accepted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.strings.text(
          widget.existing != null || widget.recurringExpense != null
              ? 'editPlan'
              : (_kind == 'goal' ? 'addGoal' : 'addPlannedExpense'),
        ),
      ),
      content: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                autofocus: true,
                textInputAction: TextInputAction.next,
                controller: _description,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: widget.strings.text('description'),
                  errorText: _missingFields && _description.text.trim().isEmpty
                      ? widget.strings.text('requiredField')
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                inputFormatters: [
                  PouchMoneyInputFormatter(widget.strings.language),
                ],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.strings.text('amount'),
                  errorText:
                      _missingFields &&
                          (parseMoneyEntry(_amount.text) ?? 0) <= 0
                      ? widget.strings.text('positiveAmount')
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              if (_repeat == 'once' && widget.recurringExpense == null)
                DropdownButtonFormField<String>(
                  key: const ValueKey('planned-category'),
                  initialValue: _category,
                  isExpanded: true,
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
                  onChanged: (value) =>
                      setState(() => _category = value ?? 'other'),
                ),
              const SizedBox(height: 10),
              ListTile(
                key: const ValueKey('planned-date'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.strings.text(
                    _kind == 'goal' ? 'targetDate' : 'dueDate',
                  ),
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
                    lastDate: lastPouchRecordDate,
                  );
                  if (mounted && picked != null) {
                    setState(() => _date = picked);
                  }
                },
              ),
              if (_kind == 'expense' && widget.existing == null) ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('bill-repeat'),
                  initialValue: _repeat,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: widget.strings.text('billRepeat'),
                  ),
                  items: [
                    for (final value in [
                      'once',
                      'weekly',
                      'biweekly',
                      'monthly',
                      'custom',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          widget.strings.text(
                            value == 'once' ? 'repeatNever' : 'schedule_$value',
                          ),
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _repeat = value!),
                ),
                if (_repeat == 'custom')
                  TextField(
                    controller: _days,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: widget.strings.text('intervalDays'),
                      errorText:
                          _missingFields &&
                              (int.tryParse(localizedInteger(_days.text)) ??
                                      0) <=
                                  0
                          ? widget.strings.text('positivePeriodDays')
                          : null,
                    ),
                  ),
                if (_repeat != 'once')
                  Text(widget.strings.text('recurringBillCategoryHint')),
              ],
              if (_repeat == 'once' && widget.recurringExpense == null)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(widget.strings.text('moreOptions')),
                  children: [
                    PouchPeriodSelector(
                      bridge: widget.bridge,
                      calendar: widget.calendar,
                      periods: widget.periods,
                      selectedId: _periodId,
                      strings: widget.strings,
                      onChanged: (id) => setState(() => _periodId = id),
                    ),
                    Text(widget.strings.text('plannedEntryHint')),
                  ],
                ),
              if (widget.recurringExpense != null)
                Text(widget.strings.text('essentialCorrectionHint')),
              if (_saveError != null)
                Text(
                  widget.strings.text(_saveError!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(widget.strings.text('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(widget.strings.text(_saving ? 'savingEntry' : 'save')),
        ),
      ],
    ),
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
    content: SingleChildScrollView(
      child: Column(
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
              if (mounted && picked != null) {
                setState(() => _date = picked);
              }
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
    this.periodId,
    this.repeat,
    this.customDays,
  );
  final String description, amount, category, kind, date, repeat;
  final String? periodId;
  final int customDays;
}

class _PaymentValues {
  const _PaymentValues(this.date, this.amount);
  final String date;
  final String amount;
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
