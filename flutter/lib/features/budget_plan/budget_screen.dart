import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({
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
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  static const _lastIncomeDate = '9998-12-31';
  static const _lastPersianCalendarDate = '3797-12-31';

  String get _lastCalendarDate =>
      widget.snapshot.preferences.calendar == 'persian'
      ? _lastPersianCalendarDate
      : _lastIncomeDate;

  late final TextEditingController _savings = TextEditingController();
  late final TextEditingController _incomeAmount = TextEditingController();
  late final List<_ExpenseDraft> _expenses = [];
  late String _effective = widget.today;
  late String _incomeDate = widget.today;
  late Future<PouchCalendarMonth> _salaryMonth = widget.bridge.calendarMonth(
    widget.today,
    widget.snapshot.preferences.calendar,
    0,
  );
  late Future<List<PouchCalendarMonth>> _salaryMonthBounds = Future.wait([
    widget.bridge.calendarMonth(
      firstPouchRecordDate,
      widget.snapshot.preferences.calendar,
      0,
    ),
    widget.bridge.calendarMonth(
      _lastCalendarDate,
      widget.snapshot.preferences.calendar,
      0,
    ),
  ]);
  String? _editingIncomeId;
  String? _editingExpectedIncomeId;
  String? _editingPlanEffective;
  bool _advancedDate = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.snapshot.planAt(widget.today);
    _savings.text = amountInput(
      plan.savings,
      language: widget.strings.language,
    );
    for (final expense in plan.expenses) {
      _expenses.add(
        _ExpenseDraft(
          expense.id,
          expense.name,
          amountInput(expense.amount, language: widget.strings.language),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant BudgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.preferences.calendar !=
            widget.snapshot.preferences.calendar ||
        oldWidget.snapshot.startDate != widget.snapshot.startDate ||
        oldWidget.today != widget.today) {
      _salaryMonth = widget.bridge.calendarMonth(
        _incomeDate,
        widget.snapshot.preferences.calendar,
        0,
      );
      _salaryMonthBounds = Future.wait([
        widget.bridge.calendarMonth(
          firstPouchRecordDate,
          widget.snapshot.preferences.calendar,
          0,
        ),
        widget.bridge.calendarMonth(
          _lastCalendarDate,
          widget.snapshot.preferences.calendar,
          0,
        ),
      ]);
    }
  }

  @override
  void dispose() {
    _savings.dispose();
    _incomeAmount.dispose();
    for (final expense in _expenses) {
      expense.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final income = [...widget.snapshot.income]
      ..sort((a, b) => b.date.compareTo(a.date));
    final expectedIncome = [...widget.snapshot.expectedIncome]
      ..sort((a, b) => b.date.compareTo(a.date));
    final plans = [...widget.snapshot.plans]
      ..sort((a, b) => a.effective.compareTo(b.effective));
    final isEditingIncome =
        _editingIncomeId != null || _editingExpectedIncomeId != null;
    final isExpectedIncome =
        _editingExpectedIncomeId != null ||
        _incomeDate.compareTo(widget.today) > 0;
    var incomeActionLabel = strings.text(
      isExpectedIncome ? 'saveExpectedIncome' : 'saveSalary',
    );
    var incomeActionIcon = Icons.add_rounded;
    if (isEditingIncome) {
      incomeActionLabel = strings.text('saveChanges');
      incomeActionIcon = Icons.save_outlined;
    }
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('budgetLabel'),
          title: strings.text('planTitle'),
          description: strings.text('budgetPageHint'),
        ),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSectionHeading(title: strings.text('salaryCalendar')),
              const SizedBox(height: 6),
              Text(
                strings.text('incomeStart'),
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  height: 1.55,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child: TextField(
                      controller: _incomeAmount,
                      inputFormatters: [
                        PouchMoneyInputFormatter(widget.strings.language),
                      ],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: strings.text(
                          isExpectedIncome
                              ? 'expectedIncomeAmount'
                              : 'salaryAmount',
                        ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickIncomeDate,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${strings.text('date')}: '),
                        PouchDateLabel(
                          bridge: widget.bridge,
                          strings: strings,
                          date: _incomeDate,
                          calendar: widget.snapshot.preferences.calendar,
                        ),
                      ],
                    ),
                  ),
                  PouchPrimaryButton(
                    label: incomeActionLabel,
                    icon: incomeActionIcon,
                    onPressed: _recordIncome,
                  ),
                  if (isExpectedIncome)
                    SizedBox(
                      width: 300,
                      child: Text(
                        strings.text('expectedIncomeHint'),
                        style: TextStyle(
                          color: context.pouchPalette.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  if (isEditingIncome)
                    TextButton(
                      onPressed: _cancelIncomeEdit,
                      child: Text(strings.text('cancel')),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSalaryCalendar(income),
              const SizedBox(height: 12),
              if (income.isEmpty && expectedIncome.isEmpty)
                Text(
                  strings.text('noSalaryEntries'),
                  style: TextStyle(color: context.pouchPalette.muted),
                ),
              for (final entry in income)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.payments_outlined,
                    color: context.pouchPalette.goldDeep,
                  ),
                  title: Text(
                    formatMoney(
                      entry.amount,
                      widget.snapshot.preferences.currency,
                      strings,
                    ),
                  ),
                  subtitle: PouchDateLabel(
                    bridge: widget.bridge,
                    strings: strings,
                    date: entry.date,
                    calendar: widget.snapshot.preferences.calendar,
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: strings.text('edit'),
                        onPressed: () => _editIncome(entry),
                        icon: Icon(
                          Icons.edit_outlined,
                          color: context.pouchPalette.goldDeep,
                        ),
                      ),
                      IconButton(
                        tooltip: strings.text('deleteSalary'),
                        onPressed: () => _removeIncome(entry),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: context.pouchPalette.goldDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final entry in expectedIncome)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.event_note_outlined,
                    color: context.pouchPalette.goldDeep,
                  ),
                  title: Text(
                    formatMoney(
                      entry.amount,
                      widget.snapshot.preferences.currency,
                      strings,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.text('expectedShort')),
                      PouchDateLabel(
                        bridge: widget.bridge,
                        strings: strings,
                        date: entry.date,
                        calendar: widget.snapshot.preferences.calendar,
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: strings.text('moreOptions'),
                    onSelected: (action) {
                      if (action == 'receive') {
                        _markExpectedIncomeReceived(entry);
                      } else if (action == 'edit') {
                        _editExpectedIncome(entry);
                      } else if (action == 'delete') {
                        _removeExpectedIncome(entry);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'receive',
                        child: Text(strings.text('markIncomeReceived')),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(strings.text('edit')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(strings.text('deleteSalary')),
                      ),
                    ],
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
              PouchSectionHeading(title: strings.text('monthlyPlan')),
              const SizedBox(height: 7),
              Text(
                strings.text('planHint'),
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 15),
              if (plans.length > 1) ...[
                Text(
                  strings.text('scheduledPlans'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final plan in plans.where(
                  (value) => value.effective.compareTo(widget.today) > 0,
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Text('${strings.text('effective')}: '),
                        PouchDateLabel(
                          bridge: widget.bridge,
                          strings: strings,
                          date: plan.effective,
                          calendar: widget.snapshot.preferences.calendar,
                        ),
                      ],
                    ),
                    subtitle: Text(
                      formatMoney(
                        plan.savings,
                        widget.snapshot.preferences.currency,
                        strings,
                      ),
                    ),
                    trailing: Wrap(
                      spacing: 2,
                      children: [
                        IconButton(
                          tooltip: strings.text('edit'),
                          onPressed: () => _editScheduledPlan(plan),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: context.pouchPalette.goldDeep,
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('delete'),
                          onPressed: () => _removeScheduledPlan(plan),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: context.pouchPalette.goldDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _savings,
                inputFormatters: [
                  PouchMoneyInputFormatter(widget.strings.language),
                ],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: strings.text('monthlySavings'),
                  helperText: strings.text('savingsHint'),
                ),
              ),
              const SizedBox(height: 14),
              PouchSectionHeading(
                title: strings.text('commitments'),
                trailing: IconButton(
                  tooltip: strings.text('addExpense'),
                  onPressed: () => setState(
                    () => _expenses.add(_ExpenseDraft(_newId(), '', '')),
                  ),
                  icon: Icon(
                    Icons.add_circle_outline_rounded,
                    color: context.pouchPalette.goldDeep,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_expenses.isEmpty)
                Text(
                  strings.text('empty'),
                  style: TextStyle(color: context.pouchPalette.muted),
                )
              else
                for (final expense in _expenses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: expense.name,
                            decoration: InputDecoration(
                              labelText: strings.text('expenseName'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: expense.amount,
                            inputFormatters: [
                              PouchMoneyInputFormatter(widget.strings.language),
                            ],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: strings.text('amount'),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('remove'),
                          onPressed: () => setState(() {
                            _expenses.remove(expense);
                            expense.dispose();
                          }),
                          icon: Icon(
                            Icons.remove_circle_outline_rounded,
                            color: context.pouchPalette.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _advancedDate,
                onChanged: (value) =>
                    setState(() => _advancedDate = value ?? false),
                title: Text(strings.text('advancedDate')),
                subtitle: Text(strings.text('advancedDateHint')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_advancedDate)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: _pickEffectiveDate,
                    icon: const Icon(Icons.event_available_rounded),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${strings.text('effective')}: '),
                        PouchDateLabel(
                          bridge: widget.bridge,
                          strings: strings,
                          date: _effective,
                          calendar: widget.snapshot.preferences.calendar,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PouchPrimaryButton(
                  label: strings.text('savePlan'),
                  icon: Icons.save_outlined,
                  onPressed: _savePlan,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSalaryCalendar(List<PouchIncome> income) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.pouchPalette.surfaceWarm,
      border: Border.all(color: context.pouchPalette.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: FutureBuilder<List<PouchCalendarMonth>>(
      future: _salaryMonthBounds,
      builder: (context, bounds) {
        if (!bounds.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return FutureBuilder<PouchCalendarMonth>(
          future: _salaryMonth,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(widget.strings.text('invalidDate'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final month = snapshot.data!;
            final firstIndex = _calendarMonthIndex(bounds.data![0]);
            final lastIndex = _calendarMonthIndex(bounds.data![1]);
            final currentIndex = _calendarMonthIndex(month);
            final firstOffset =
                (month.firstWeekday -
                    widget.snapshot.preferences.weekStart +
                    7) %
                7;
            final cellCount = ((firstOffset + month.dayCount + 6) ~/ 7) * 7;
            final incomeByDate = {for (final item in income) item.date: item};
            final expectedByDate = {
              for (final item in widget.snapshot.expectedIncome)
                item.date: item,
            };
            final weekdays = List.generate(7, (index) {
              final weekday =
                  (widget.snapshot.preferences.weekStart + index) % 7;
              return DateFormat.E(widget.strings.language)
                  .format(DateTime.utc(2023, 1, weekday + 1));
            });
            return Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: widget.strings.text('previousMonth'),
                      onPressed: currentIndex <= firstIndex
                          ? null
                          : () => _shiftSalaryMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _salaryMonthTitle(month),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: widget.strings.text('nextMonth'),
                      onPressed: currentIndex >= lastIndex
                          ? null
                          : () => _shiftSalaryMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final day in weekdays)
                      Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: TextStyle(
                              color: context.pouchPalette.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: cellCount,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 58,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemBuilder: (context, index) {
                    final day = index - firstOffset + 1;
                    if (day < 1 || day > month.dayCount) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime.parse('${month.startDate}T00:00:00Z')
                        .add(Duration(days: day - 1))
                        .toIso8601String()
                        .substring(0, 10);
                    final entry = incomeByDate[date];
                    final expected = expectedByDate[date];
                    final incomeAmount = entry?.amount ?? expected?.amount;
                    final selected = date == _incomeDate;
                    final enabled = date.compareTo(firstPouchRecordDate) >= 0;
                    return InkWell(
                      onTap: enabled
                          ? () => _selectIncomeDate(
                              date,
                              income: entry,
                              expected: expected,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? context.pouchPalette.goldDeep
                              : null,
                          border: entry == null && expected == null
                              ? null
                              : Border.all(
                                  color: selected
                                      ? context.pouchPalette.goldPale
                                      : expected != null
                                      ? context.pouchPalette.gold
                                      : context.pouchPalette.goldBright,
                                ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              localizeDigits('$day', widget.strings.language),
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : enabled
                                    ? context.pouchPalette.ink
                                    : context.pouchPalette.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (incomeAmount != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                widget.strings.text(
                                  expected == null ? 'salary' : 'expectedShort',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: selected
                                      ? context.pouchPalette.goldPale
                                      : context.pouchPalette.goldDeep,
                                  fontSize: 7,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  formatMoney(
                                    incomeAmount,
                                    widget.snapshot.preferences.currency,
                                    widget.strings,
                                  ),
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : context.pouchPalette.ink,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${widget.strings.text('date')}: ',
                      style: TextStyle(
                        color: context.pouchPalette.muted,
                        fontSize: 11,
                      ),
                    ),
                    PouchDateLabel(
                      bridge: widget.bridge,
                      strings: widget.strings,
                      date: _incomeDate,
                      calendar: widget.snapshot.preferences.calendar,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ),
  );

  void _shiftSalaryMonth(int count) {
    final current = _salaryMonth;
    setState(() {
      _salaryMonth = current.then(
        (month) => widget.bridge.calendarMonth(
          month.startDate,
          widget.snapshot.preferences.calendar,
          count,
        ),
      );
    });
  }

  String _salaryMonthTitle(PouchCalendarMonth month) {
    if (widget.snapshot.preferences.calendar == 'gregory') {
      return DateFormat.MMMM(widget.strings.language)
          .format(DateTime.utc(month.year, month.month));
    }
    const english = [
      'Farvardin',
      'Ordibehesht',
      'Khordad',
      'Tir',
      'Mordad',
      'Shahrivar',
      'Mehr',
      'Aban',
      'Azar',
      'Dey',
      'Bahman',
      'Esfand',
    ];
    const persian = [
      'فروردین',
      'اردیبهشت',
      'خرداد',
      'تیر',
      'مرداد',
      'شهریور',
      'مهر',
      'آبان',
      'آذر',
      'دی',
      'بهمن',
      'اسفند',
    ];
    final names = widget.strings.isPersian ? persian : english;
    final year = localizeDigits('${month.year}', widget.strings.language);
    return '${names[month.month - 1]} $year';
  }

  int _calendarMonthIndex(PouchCalendarMonth month) =>
      month.year * 12 + month.month;

  Future<void> _savePlan() async {
    final expenses = <PouchExpenseDraft>[];
    for (final expense in _expenses) {
      if (expense.name.text.trim().isEmpty &&
          expense.amount.text.trim().isEmpty) {
        continue;
      }
      expenses.add(
        PouchExpenseDraft(
          expense.id,
          expense.name.text.trim(),
          expense.amount.text.trim(),
        ),
      );
    }
    final effective =
        _editingPlanEffective ?? (_advancedDate ? _effective : widget.today);
    final accepted = await widget.run(
      () => widget.bridge.saveBudgetPlan(
        effective: effective,
        salary: null,
        dailyBudget: '0',
        expenses: expenses,
        savings: _savings.text.trim().isEmpty ? '0' : _savings.text.trim(),
        payday: 1,
      ),
    );
    if (accepted && mounted) {
      if (_editingPlanEffective != null) {
        setState(() {
          _editingPlanEffective = null;
          _advancedDate = false;
          _effective = widget.today;
          _loadPlan(widget.snapshot.planAt(widget.today));
        });
      }
      showPouchMessage(context, widget.strings, 'settingsSaved');
    }
  }

  void _loadPlan(PouchBudgetPlan plan) {
    _savings.text = amountInput(
      plan.savings,
      language: widget.strings.language,
    );
    for (final expense in _expenses) {
      expense.dispose();
    }
    _expenses
      ..clear()
      ..addAll(
        plan.expenses.map(
          (expense) => _ExpenseDraft(
            expense.id,
            expense.name,
            amountInput(expense.amount, language: widget.strings.language),
          ),
        ),
      );
  }

  void _editScheduledPlan(PouchBudgetPlan plan) {
    setState(() {
      _editingPlanEffective = plan.effective;
      _effective = plan.effective;
      _advancedDate = true;
      _loadPlan(plan);
    });
  }

  Future<void> _removeScheduledPlan(PouchBudgetPlan plan) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('delete')),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PouchDateLabel(
              bridge: widget.bridge,
              strings: widget.strings,
              date: plan.effective,
              calendar: widget.snapshot.preferences.calendar,
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(
                plan.savings,
                widget.snapshot.preferences.currency,
                widget.strings,
              ),
            ),
          ],
        ),
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
      () => widget.bridge.removeBudgetPlan(plan.effective),
    );
    if (!deleted || !mounted) return;
    if (_editingPlanEffective == plan.effective) {
      setState(() {
        _editingPlanEffective = null;
        _advancedDate = false;
        _effective = widget.today;
        _loadPlan(widget.snapshot.planAt(widget.today));
      });
    }
    showPouchUndoMessage(context, widget.strings, 'deleted', widget.undo);
  }

  Future<void> _recordIncome() async {
    final editingId = _editingIncomeId;
    final editingExpectedId = _editingExpectedIncomeId;
    final accepted = await widget.run(() {
      if (editingExpectedId != null) {
        return widget.bridge.updateExpectedIncome(
          id: editingExpectedId,
          date: _incomeDate,
          amount: _incomeAmount.text.trim(),
        );
      }
      if (editingId != null) {
        return widget.bridge.updateIncome(
          id: editingId,
          date: _incomeDate,
          amount: _incomeAmount.text.trim(),
        );
      }
      if (_incomeDate.compareTo(widget.today) > 0) {
        return widget.bridge.scheduleIncome(
          id: _newId(),
          date: _incomeDate,
          amount: _incomeAmount.text.trim(),
        );
      }
      return widget.bridge.recordIncome(
        id: _newId(),
        date: _incomeDate,
        amount: _incomeAmount.text.trim(),
      );
    });
    if (accepted && mounted) {
      _incomeAmount.clear();
      setState(() {
        _editingIncomeId = null;
        _editingExpectedIncomeId = null;
      });
      var messageKey = 'salarySaved';
      if (editingExpectedId != null) {
        messageKey = 'expectedIncomeUpdated';
      } else if (editingId != null) {
        messageKey = 'salaryUpdated';
      } else if (_incomeDate.compareTo(widget.today) > 0) {
        messageKey = 'expectedIncomeSaved';
      }
      showPouchMessage(context, widget.strings, messageKey);
    }
  }

  void _editIncome(PouchIncome income) {
    setState(() {
      _editingIncomeId = income.id;
      _editingExpectedIncomeId = null;
      _incomeDate = income.date;
      _incomeAmount.text = amountInput(
        income.amount,
        language: widget.strings.language,
      );
      _salaryMonth = widget.bridge.calendarMonth(
        income.date,
        widget.snapshot.preferences.calendar,
        0,
      );
    });
  }

  void _editExpectedIncome(PouchExpectedIncome income) {
    setState(() {
      _editingIncomeId = null;
      _editingExpectedIncomeId = income.id;
      _incomeDate = income.date;
      _incomeAmount.text = amountInput(
        income.amount,
        language: widget.strings.language,
      );
      _salaryMonth = widget.bridge.calendarMonth(
        income.date,
        widget.snapshot.preferences.calendar,
        0,
      );
    });
  }

  void _cancelIncomeEdit() {
    setState(() {
      _editingIncomeId = null;
      _editingExpectedIncomeId = null;
      _incomeDate = widget.today;
      _incomeAmount.clear();
    });
  }

  Future<void> _removeIncome(PouchIncome income) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('deleteSalary')),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PouchDateLabel(
              bridge: widget.bridge,
              strings: widget.strings,
              date: income.date,
              calendar: widget.snapshot.preferences.calendar,
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(
                income.amount,
                widget.snapshot.preferences.currency,
                widget.strings,
              ),
            ),
          ],
        ),
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
    if (confirm != true) return;
    final accepted = await widget.run(
      () => widget.bridge.removeIncome(income.id),
    );
    if (accepted && mounted) {
      if (_editingIncomeId == income.id) _cancelIncomeEdit();
      showPouchUndoMessage(
        context,
        widget.strings,
        'salaryDeleted',
        widget.undo,
      );
    }
  }

  Future<void> _removeExpectedIncome(PouchExpectedIncome income) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('deleteSalary')),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PouchDateLabel(
              bridge: widget.bridge,
              strings: widget.strings,
              date: income.date,
              calendar: widget.snapshot.preferences.calendar,
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(
                income.amount,
                widget.snapshot.preferences.currency,
                widget.strings,
              ),
            ),
          ],
        ),
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
    if (confirm != true) return;
    final accepted = await widget.run(
      () => widget.bridge.removeExpectedIncome(income.id),
    );
    if (accepted && mounted) {
      if (_editingExpectedIncomeId == income.id) _cancelIncomeEdit();
      showPouchUndoMessage(
        context,
        widget.strings,
        'expectedIncomeDeleted',
        widget.undo,
      );
    }
  }

  Future<void> _markExpectedIncomeReceived(PouchExpectedIncome income) async {
    final receivedDate = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: income.date.compareTo(widget.today) > 0
          ? widget.today
          : income.date,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: firstPouchRecordDate,
      lastDate: widget.today,
    );
    if (receivedDate == null) return;
    final accepted = await widget.run(
      () => widget.bridge.markExpectedIncomeReceived(
        id: income.id,
        receivedDate: receivedDate,
      ),
    );
    if (accepted && mounted) {
      if (_editingExpectedIncomeId == income.id) _cancelIncomeEdit();
      showPouchMessage(context, widget.strings, 'expectedIncomeReceived');
    }
  }

  Future<void> _pickIncomeDate() async {
    final picked = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: _incomeDate,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: firstPouchRecordDate,
      lastDate: _lastIncomeDate,
    );
    if (picked != null) {
      final existingIncome = widget.snapshot.income.where(
        (value) => value.date == picked,
      );
      final existingExpected = widget.snapshot.expectedIncome.where(
        (value) => value.date == picked,
      );
      _selectIncomeDate(
        picked,
        income: existingIncome.isEmpty ? null : existingIncome.first,
        expected: existingExpected.isEmpty ? null : existingExpected.first,
      );
      setState(() {
        _salaryMonth = widget.bridge.calendarMonth(
          picked,
          widget.snapshot.preferences.calendar,
          0,
        );
      });
    }
  }

  Future<void> _pickEffectiveDate() async {
    final picked = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: _effective.compareTo(widget.today) < 0
          ? widget.today
          : _effective,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: widget.today,
      lastDate: _lastIncomeDate,
    );
    if (picked != null) setState(() => _effective = picked);
  }

  void _selectIncomeDate(
    String date, {
    PouchIncome? income,
    PouchExpectedIncome? expected,
  }) {
    setState(() {
      _incomeDate = date;
      if (_editingIncomeId != null || _editingExpectedIncomeId != null) {
        return;
      }
      _editingIncomeId = income?.id;
      _editingExpectedIncomeId = expected?.id;
      final amount = income?.amount ?? expected?.amount;
      if (amount == null) {
        _incomeAmount.clear();
      } else {
        _incomeAmount.text = amountInput(
          amount,
          language: widget.strings.language,
        );
      }
    });
  }
}

class _ExpenseDraft {
  _ExpenseDraft(this.id, String name, String amount)
    : name = TextEditingController(text: name),
      amount = TextEditingController(text: amount);

  final String id;
  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
