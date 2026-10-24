import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_motion.dart';
import '../../widgets/pouch_period_selector.dart';
import '../../widgets/pouch_date_picker.dart';
import 'period_controls.dart';
import 'budget_setup.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    required this.undo,
    this.onSetupComplete,
    this.focusIncome = false,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final PouchUndo undo;
  final VoidCallback? onSetupComplete;
  final bool focusIncome;

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
  PouchPeriodView? _periodView;
  late String _planDate = widget.today;
  int _periodRequest = 0;
  bool _periodLoading = false;
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
  bool _deletingSavings = false;
  String? _observedPeriodId;
  final _incomeButton = GlobalKey();
  final _incomeFormKey = GlobalKey();
  final _savingsButton = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadPlan(widget.snapshot.currentPlan);
    if (widget.focusIncome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _incomeFormKey.currentContext;
        if (context != null) Scrollable.ensureVisible(context, alignment: 0.1);
      });
    }
    if (widget.snapshot.currentPeriod != null) {
      _selectPeriod(widget.today);
    } else if (widget.snapshot.periods.isNotEmpty) {
      _selectPeriod(widget.snapshot.periods.last.start);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selected = selectedPouchPeriod(
      widget.snapshot,
      PouchPeriodScope.maybeOf(context)?.periodId,
    );
    if (selected != null && selected.id != _observedPeriodId) {
      _observedPeriodId = selected.id;
      _selectPeriod(selected.start);
    }
  }

  void _choosePeriodAtDate(String date) {
    _selectPeriod(date, publish: true);
  }

  @override
  void didUpdateWidget(covariant BudgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.revision != widget.snapshot.revision) {
      final selected = selectedPouchPeriod(
        widget.snapshot,
        PouchPeriodScope.maybeOf(context)?.periodId ?? _periodView?.period.id,
      );
      if (selected != null) {
        _selectPeriod(selected.start);
      } else {
        _periodRequest++;
        _periodView = null;
        _periodLoading = false;
        _observedPeriodId = null;
      }
    }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.strings;
    final editing =
        _editingIncomeId != null || _editingExpectedIncomeId != null;
    final expected =
        _editingExpectedIncomeId != null ||
        _incomeDate.compareTo(widget.today) > 0;
    final view = _periodView;
    final income = view?.income ?? widget.snapshot.income;
    final expectedIncome =
        view?.expectedIncome ?? widget.snapshot.expectedIncome;
    final planRevisions = widget.snapshot.plans.where(
      (plan) => plan.periodId == view?.period.id,
    );
    final incomeForm = PouchCard(
      key: _incomeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(
            title: t.text(editing ? 'editIncome' : 'recordIncomeTitle'),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            key: const ValueKey('income-calendar'),
            tilePadding: EdgeInsets.zero,
            title: PouchDateLabel(
              bridge: widget.bridge,
              strings: t,
              date: _incomeDate,
              calendar: widget.snapshot.preferences.calendar,
            ),
            subtitle: Text(t.text('changeIncomeDate')),
            children: [_buildSalaryCalendar(income)],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _incomeAmount,
            inputFormatters: [PouchMoneyInputFormatter(t.language)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t.text(
                expected ? 'expectedIncomeAmount' : 'salaryAmount',
              ),
            ),
          ),
          const SizedBox(height: 12),
          PouchPrimaryButton(
            key: _incomeButton,
            label: t.text(editing ? 'saveIncome' : 'addIncome'),
            icon: Icons.add_rounded,
            onPressed: _periodLoading ? null : _recordIncome,
          ),
          if (expected)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(t.text('expectedIncomeHint')),
            ),
          if (editing)
            TextButton(
              onPressed: _cancelIncomeEdit,
              child: Text(t.text('cancel')),
            ),
        ],
      ),
    );
    final periodControls = PeriodControls(
      bridge: widget.bridge,
      snapshot: widget.snapshot,
      strings: t,
      today: widget.today,
      view: view,
      run: widget.run,
      select: _choosePeriodAtDate,
    );
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: t.text('budgetLabel'),
          title: t.text('planTitle'),
          description: t.text('budgetPageHint'),
        ),
        if (widget.snapshot.periods.isEmpty)
          PouchEmptyState(
            title: t.text('firstPeriodTitle'),
            message: t.text('setupWelcome'),
            action: FilledButton(
              onPressed: () async {
                final done = await showBudgetSetup(
                  context: context,
                  bridge: widget.bridge,
                  snapshot: widget.snapshot,
                  strings: t,
                  today: widget.today,
                  run: widget.run,
                );
                if (done && mounted) widget.onSetupComplete?.call();
              },
              child: Text(t.text('setupStart')),
            ),
          ),
        if (widget.snapshot.periods.isEmpty)
          ExpansionTile(
            title: Text(t.text('manualBudgetDates')),
            children: [periodControls],
          )
        else
          periodControls,
        const SizedBox(height: 24),
        if (_periodLoading) const LinearProgressIndicator(),
        if (widget.snapshot.periods.isNotEmpty) incomeForm,
        const SizedBox(height: 20),
        if (view != null) ...[
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PouchSectionHeading(title: t.text('periodSavings')),
                PouchPeriodNotice(strings: t, period: view.period),
                const SizedBox(height: 8),
                Text(t.text('savingsHint')),
                const SizedBox(height: 16),
                TextField(
                  controller: _savings,
                  inputFormatters: [PouchMoneyInputFormatter(t.language)],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: t.text('periodSavings'),
                  ),
                ),
                ExpansionTile(
                  key: ValueKey('effective-options-$_advancedDate'),
                  initiallyExpanded: _advancedDate,
                  tilePadding: EdgeInsets.zero,
                  title: Text(t.text('moreOptions')),
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.text('advancedDate')),
                      value: _advancedDate,
                      onChanged: (value) =>
                          setState(() => _advancedDate = value!),
                    ),
                    if (_advancedDate)
                      TextButton(
                        onPressed: _pickEffectiveDate,
                        child: PouchDateLabel(
                          bridge: widget.bridge,
                          strings: t,
                          date: _effective,
                          calendar: widget.snapshot.preferences.calendar,
                        ),
                      ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: PouchPrimaryButton(
                    key: _savingsButton,
                    label: t.text('savePlan'),
                    onPressed: _periodLoading ? null : _savePlan,
                  ),
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(t.text('budgetBreakdown')),
                  children: [
                    for (final entry in [
                      ('freeToSpend', view.budget.remaining),
                      ('reservedExpenses', view.budget.fundedExpenses),
                      ('protectedSavings', view.budget.savings),
                      ('carry', view.budget.carry),
                    ])
                      PouchSummaryRow(
                        label: t.text(entry.$1),
                        value: _money(entry.$2),
                      ),
                    Text(t.text('savingsSetAsideHint')),
                  ],
                ),
                if (planRevisions.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    key: const ValueKey('savings-history'),
                    title: Text(t.text('planHistory')),
                    children: [
                      for (final plan in planRevisions)
                        ListTile(
                          key: ValueKey('savings-plan-${plan.effective}'),
                          title: Text(_money(plan.savings)),
                          subtitle: PouchDateLabel(
                            bridge: widget.bridge,
                            strings: t,
                            date: plan.effective,
                            calendar: widget.snapshot.preferences.calendar,
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: t.text('edit'),
                                onPressed: _deletingSavings
                                    ? null
                                    : () => _editSavings(plan),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'delete-savings-${plan.effective}',
                                ),
                                tooltip: t.text('delete'),
                                onPressed: _deletingSavings
                                    ? null
                                    : () => _deleteSavings(plan),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (view.obligations.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(t.text('periodObligations')),
                    children: [
                      for (final item in view.obligations)
                        ListTile(
                          title: Text(item.description),
                          subtitle: PouchDateLabel(
                            bridge: widget.bridge,
                            strings: t,
                            date: item.date,
                            calendar: widget.snapshot.preferences.calendar,
                          ),
                          trailing: Text(_money(item.amount)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (widget.snapshot.periods.isNotEmpty)
          PouchCard(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(t.text('incomeHistory')),
              children: [
                if (income.isEmpty && expectedIncome.isEmpty)
                  Text(t.text('noIncomeYet')),
                for (final item in income.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.south_west_rounded),
                    title: Text(_money(item.amount)),
                    subtitle: PouchDateLabel(
                      bridge: widget.bridge,
                      strings: t,
                      date: item.date,
                      calendar: widget.snapshot.preferences.calendar,
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: t.text('edit'),
                          onPressed: () => _editIncome(item),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: t.text('delete'),
                          onPressed: () => _removeIncome(item),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                for (final item in expectedIncome.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(
                      '${t.text('expectedShort')} · ${_money(item.amount)}',
                    ),
                    subtitle: PouchDateLabel(
                      bridge: widget.bridge,
                      strings: t,
                      date: item.date,
                      calendar: widget.snapshot.preferences.calendar,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'receive') {
                          _markExpectedIncomeReceived(item);
                        }
                        if (action == 'edit') _editExpectedIncome(item);
                        if (action == 'delete') _removeExpectedIncome(item);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'receive',
                          child: Text(t.text('receivedIncome')),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(t.text('edit')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(t.text('delete')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _money(int value) =>
      formatMoney(value, widget.snapshot.preferences.currency, widget.strings);

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
            final totalsByDate = <String, int>{};
            for (final item in income) {
              totalsByDate.update(
                item.date,
                (amount) => amount + item.amount,
                ifAbsent: () => item.amount,
              );
            }
            final expectedIncome =
                _periodView?.expectedIncome ?? widget.snapshot.expectedIncome;
            final expectedByDate = {
              for (final item in expectedIncome) item.date: item,
            };
            final expectedTotalsByDate = <String, int>{};
            for (final item in expectedIncome) {
              expectedTotalsByDate.update(
                item.date,
                (amount) => amount + item.amount,
                ifAbsent: () => item.amount,
              );
            }
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
                    final incomeAmount = totalsByDate[date];
                    final expectedAmount = expectedTotalsByDate[date];
                    final selected = date == _incomeDate;
                    final enabled = date.compareTo(firstPouchRecordDate) >= 0;
                    return InkWell(
                      key: ValueKey('income-date-$date'),
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
                              : (_periodView != null &&
                                        date.compareTo(
                                              _periodView!.period.start,
                                            ) >=
                                            0 &&
                                        date.compareTo(
                                              _periodView!.period.end,
                                            ) <=
                                            0
                                    ? context.pouchPalette.surfaceWarm
                                    : null),
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
                            if (expectedAmount != null && expectedAmount > 0)
                              Text(
                                '${widget.strings.text('expectedShort')}: ${formatMoney(expectedAmount, widget.snapshot.preferences.currency, widget.strings)}',
                                maxLines: 1,
                                style: const TextStyle(fontSize: 8),
                              ),
                            if (incomeAmount != null && incomeAmount > 0) ...[
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

  Future<void> _selectPeriod(String date, {bool publish = false}) async {
    final request = ++_periodRequest;
    setState(() => _periodLoading = true);
    try {
      final view = await widget.bridge.periodView(date);
      if (!mounted || request != _periodRequest) return;
      setState(() {
        _periodLoading = false;
        _periodView = view;
        _planDate = view.budget.date;
        _effective = view.budget.date;
        _editingPlanEffective = null;
        _advancedDate = false;
        _loadPlan(view.plan);
        if (publish) _observedPeriodId = view.period.id;
      });
      if (publish) PouchPeriodScope.maybeOf(context)?.onChanged(view.period.id);
    } catch (error) {
      if (mounted && request == _periodRequest) {
        setState(() => _periodLoading = false);
        if (widget.snapshot.currentPeriod == null) {
          setState(() => _periodView = null);
        }
        setState(() => _periodView = null);
        showPouchMessage(context, widget.strings, 'chooseHorizon');
      }
    }
  }

  Future<void> _savePlan() async {
    final period = _periodView?.period ?? widget.snapshot.currentPeriod;
    if (period == null) {
      showPouchMessage(context, widget.strings, 'chooseHorizon');
      return;
    }
    final effective =
        _editingPlanEffective ?? (_advancedDate ? _effective : _planDate);
    PouchBudgetPlan? previousPlan;
    for (final plan in widget.snapshot.plans) {
      if (plan.periodId == period.id &&
          plan.effective.compareTo(effective) <= 0 &&
          (previousPlan == null ||
              plan.effective.compareTo(previousPlan.effective) > 0)) {
        previousPlan = plan;
      }
    }
    final previousSavings = previousPlan?.savings ?? 0;
    final enteredSavings =
        NumberFormat.decimalPattern(widget.strings.language)
            .tryParse(_savings.text) ??
        0;
    final accepted = await widget.run(
      () => widget.bridge.saveBudgetPlan(
        periodId: period.id,
        effective: effective,
        savings: _savings.text.trim().isEmpty ? '0' : _savings.text.trim(),
      ),
    );
    if (accepted && mounted) {
      if (enteredSavings > previousSavings / 100) {
        PouchMotion.celebrate(context, anchor: _savingsButton);
      }
      showPouchMessage(context, widget.strings, 'settingsSaved');
    }
  }

  void _loadPlan(PouchBudgetPlan plan) {
    _savings.text = amountInput(
      plan.savings,
      language: widget.strings.language,
    );
  }

  void _editSavings(PouchBudgetPlan plan) {
    setState(() {
      _editingPlanEffective = plan.effective;
      _effective = plan.effective;
      _advancedDate = true;
      _loadPlan(plan);
    });
  }

  Future<void> _deleteSavings(PouchBudgetPlan plan) async {
    if (_deletingSavings) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('deleteSavings')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.strings.text('deleteSavingsHint')),
              const SizedBox(height: 16),
              Text(_money(plan.savings)),
              const SizedBox(height: 4),
              PouchDateLabel(
                bridge: widget.bridge,
                strings: widget.strings,
                date: plan.effective,
                calendar: widget.snapshot.preferences.calendar,
              ),
            ],
          ),
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
    if (approved != true || !mounted) return;
    setState(() => _deletingSavings = true);
    try {
      final deleted = await widget.run(
        () => widget.bridge.removeBudgetPlan(plan.effective),
      );
      if (!deleted || !mounted) return;
      if (_editingPlanEffective == plan.effective) {
        setState(() {
          _editingPlanEffective = null;
          _advancedDate = false;
          _effective = _planDate;
          _loadPlan(_periodView?.plan ?? widget.snapshot.currentPlan);
        });
      }
      showPouchUndoMessage(context, widget.strings, 'deleted', widget.undo);
    } finally {
      if (mounted) setState(() => _deletingSavings = false);
    }
  }

  Future<void> _recordIncome() async {
    final periodId = _periodView?.period.id;
    if (periodId == null) {
      showPouchMessage(context, widget.strings, 'choosePeriodHint');
      return;
    }
    final editingId = _editingIncomeId;
    final editingExpectedId = _editingExpectedIncomeId;
    if (editingId == null &&
        editingExpectedId == null &&
        _incomeDate.compareTo(widget.today) <= 0) {
      final accepted = await _receive(
        _newId(),
        _incomeDate,
        _incomeAmount.text.trim(),
      );
      if (accepted && mounted) {
        _incomeAmount.clear();
        await _selectPeriod(
          widget.snapshot.periods
              .firstWhere((period) => period.id == periodId)
              .start,
        );
      }
      return;
    }
    final accepted = await widget.run(() {
      if (editingExpectedId != null) {
        return widget.bridge.updateExpectedIncome(
          id: editingExpectedId,
          date: _incomeDate,
          amount: _incomeAmount.text.trim(),
          periodId: periodId,
        );
      }
      if (editingId != null) {
        return widget.bridge.updateIncome(
          id: editingId,
          date: _incomeDate,
          amount: _incomeAmount.text.trim(),
          periodId: periodId,
        );
      }
      if (_incomeDate.compareTo(widget.today) > 0) {
        return widget.bridge.scheduleIncome(
          id: _newId(),
          date: _incomeDate,
          amount: _incomeAmount.text.trim(),
          periodId: periodId,
        );
      }
      throw StateError('Receipt choice must be resolved first');
    });
    if (accepted && mounted) {
      PouchMotion.celebrate(context, anchor: _incomeButton);
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
    if (receivedDate == null || !mounted) return;
    final actual = await showDialog<String>(
      context: context,
      builder: (_) => _ReceivedAmountDialog(
        strings: widget.strings,
        initial: amountInput(income.amount, language: widget.strings.language),
      ),
    );
    if (actual == null) return;
    if (!mounted) return;
    final accepted = await _receive(
      income.id,
      receivedDate,
      actual,
      expected: true,
    );
    if (accepted && mounted) {
      if (_editingExpectedIncomeId == income.id) _cancelIncomeEdit();
      showPouchMessage(context, widget.strings, 'expectedIncomeReceived');
    }
  }

  Future<bool> _receive(
    String id,
    String date,
    String amount, {
    bool expected = false,
  }) async {
    final period = _periodView?.period;
    if (period == null) {
      showPouchMessage(context, widget.strings, 'choosePeriodHint');
      return false;
    }
    final accepted = await widget.run(
      () => widget.bridge.receiveIncome(
        id: id,
        date: date,
        amount: amount,
        periodId: period.id,
        startNew: false,
        expected: expected,
      ),
    );
    if (accepted && mounted) {
      PouchMotion.celebrate(context, anchor: _incomeButton);
    }
    return accepted;
  }

  Future<void> _pickEffectiveDate() async {
    final picked = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: _effective,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: _periodView?.period.start ?? widget.today,
      lastDate: _periodView?.period.end ?? _lastIncomeDate,
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
      if (_editingIncomeId == null && _editingExpectedIncomeId == null) {
        _incomeAmount.clear();
      }
    });
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

class _ReceivedAmountDialog extends StatefulWidget {
  const _ReceivedAmountDialog({required this.strings, required this.initial});
  final AppStrings strings;
  final String initial;
  @override
  State<_ReceivedAmountDialog> createState() => _ReceivedAmountDialogState();
}

class _ReceivedAmountDialogState extends State<_ReceivedAmountDialog> {
  late final amount = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.text('receivedIncome')),
    content: TextField(
      controller: amount,
      autofocus: true,
      inputFormatters: [PouchMoneyInputFormatter(widget.strings.language)],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.strings.text('amount')),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, amount.text.trim()),
        child: Text(widget.strings.text('continueIncome')),
      ),
    ],
  );
}
