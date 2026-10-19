import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';
import '../../widgets/pouch_period_selector.dart';
import '../purchases/purchases_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.selectedDate,
    required this.onDateChanged,
    required this.working,
    required this.run,
    required this.undo,
    this.onOpenBudget,
    this.onOpenPlanned,
    super.key,
  });
  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today, selectedDate;
  final ValueChanged<String> onDateChanged;
  final bool working;
  final PouchMutation run;
  final PouchUndo undo;
  final VoidCallback? onOpenBudget, onOpenPlanned;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  String? _periodId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = selectedPouchPeriod(
      widget.snapshot,
      PouchPeriodScope.maybeOf(context)?.periodId,
    )?.id;
    if (id != _periodId) {
      _periodId = id;
      summary = widget.bridge.budgetSummary(
        widget.selectedDate,
        periodId: _periodId,
      );
      tomorrow = loadTomorrow();
    }
  }

  late Future<PouchBudgetSummary> tomorrow = loadTomorrow();

  Future<PouchBudgetSummary> loadTomorrow() => widget.bridge.budgetSummary(
    DateTime.parse('${widget.today}T00:00:00Z')
        .add(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10),
    periodId: _periodId,
  );

  late Future<PouchBudgetSummary> summary = widget.bridge.budgetSummary(
    widget.selectedDate,
    periodId: _periodId,
  );

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today ||
        oldWidget.snapshot.revision != widget.snapshot.revision) {
      tomorrow = loadTomorrow();
    }
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.snapshot.revision != widget.snapshot.revision) {
      summary = widget.bridge.budgetSummary(
        widget.selectedDate,
        periodId: _periodId,
      );
    }
  }

  String money(int value) =>
      formatMoney(value, widget.snapshot.preferences.currency, widget.strings);

  Widget dateLabel(String date) => PouchDateLabel(
    bridge: widget.bridge,
    strings: widget.strings,
    date: date,
    calendar: widget.snapshot.preferences.calendar,
  );

  void step(int days) {
    final date = DateTime.parse('${widget.selectedDate}T00:00:00Z')
        .add(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    widget.onDateChanged(date);
  }

  Future<void> pickDate() async {
    final date = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: widget.selectedDate,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: firstPouchRecordDate,
      lastDate: lastPouchRecordDate,
      highlightedDates: {
        for (final day in widget.snapshot.days)
          if (day.purchases.isNotEmpty) day.date,
        for (final item in widget.snapshot.planned)
          if (item.kind == 'expense' && item.status == 'pending') item.date,
      },
    );
    if (mounted && date != null) widget.onDateChanged(date);
  }

  bool showingHistory = false;
  void history() => setState(() => showingHistory = true);

  @override
  Widget build(BuildContext context) {
    final t = widget.strings;
    final futureDay = widget.selectedDate.compareTo(widget.today) > 0;
    if (showingHistory) {
      return Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => showingHistory = false),
              icon: const BackButtonIcon(),
              label: Text(t.text('backToDay')),
            ),
          ),
          Expanded(
            child: PurchasesScreen(
              bridge: widget.bridge,
              snapshot: widget.snapshot,
              strings: t,
              today: widget.today,
              selectedDate: widget.selectedDate,
              working: widget.working,
              run: widget.run,
              undo: widget.undo,
            ),
          ),
        ],
      );
    }
    return PouchPage(
      children: [
        PouchPeriodNotice(
          key: const ValueKey('today-period-context'),
          strings: t,
          period: selectedPouchPeriod(widget.snapshot, _periodId),
        ),
        const SizedBox(height: 12),
        PouchIntro(
          eyebrow: t.text('todayLabel'),
          title: t.text('todayTitle'),
          description: t.text('todayPageHint'),
        ),
        PouchCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('previous-day'),
                    tooltip: t.text('previous'),
                    onPressed:
                        widget.selectedDate.compareTo(firstPouchRecordDate) > 0
                        ? () => step(-1)
                        : null,
                    icon: const BackButtonIcon(),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('select-day'),
                      onPressed: pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: dateLabel(widget.selectedDate),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('next-day'),
                    tooltip: t.text('next'),
                    onPressed:
                        widget.selectedDate.compareTo(lastPouchRecordDate) < 0
                        ? () => step(1)
                        : null,
                    icon: const RotatedBox(
                      quarterTurns: 2,
                      child: BackButtonIcon(),
                    ),
                  ),
                ],
              ),
              if (widget.selectedDate != widget.today)
                TextButton(
                  onPressed: () => widget.onDateChanged(widget.today),
                  child: Text(t.text('backToToday')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<PouchBudgetSummary>(
          key: ObjectKey(summary),
          future: summary,
          builder: (context, result) {
            if (result.hasError) return PouchInlineError(t.text('invalidData'));
            if (!result.hasData) return const LinearProgressIndicator();
            final value = result.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (value.date != widget.selectedDate)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FutureBuilder<String>(
                      future: formatPouchDate(
                        widget.bridge,
                        value.date,
                        widget.snapshot.preferences.calendar,
                        t,
                      ),
                      builder: (context, date) => Text(
                        t.text('periodCalculationDate', {
                          'date':
                              date.data ??
                              localizeDigits(value.date, t.language),
                        }),
                      ),
                    ),
                  ),
                if (value.daysRemaining == 0) ...[
                  PouchEmptyState(
                    title: t.text(
                      widget.snapshot.periods.isEmpty
                          ? 'firstPeriodTitle'
                          : 'noPeriodForDay',
                    ),
                    message: t.text('firstPeriodHint'),
                    action: TextButton(
                      onPressed: widget.onOpenBudget,
                      child: Text(t.text('navBudget')),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                PouchCard(
                  color: context.pouchPalette.ink,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.text(
                          value.daysRemaining == 0
                              ? (futureDay
                                    ? 'futureBalance'
                                    : 'availableBalance')
                              : (futureDay
                                    ? 'futureAllowance'
                                    : 'dayAllowance'),
                        ),
                        style: TextStyle(
                          color: context.pouchPalette.goldPale,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        money(
                          value.daysRemaining == 0
                              ? value.remaining
                              : value.recommendation,
                        ),
                        style: TextStyle(
                          color: context.pouchPalette.surface,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                      ),
                      if (futureDay) ...[
                        const SizedBox(height: 8),
                        Text(
                          t.text('futureBudgetHint'),
                          style: TextStyle(
                            color: context.pouchPalette.goldPale,
                          ),
                        ),
                      ],
                      if (value.daysRemaining > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          t.text('daysToLast', {
                            'days': localizeDigits(
                              '${value.daysRemaining}',
                              t.language,
                            ),
                          }),
                          style: TextStyle(
                            color: context.pouchPalette.goldPale,
                          ),
                        ),
                      ],
                      if (value.shortfall > 0)
                        Text(
                          '${t.text('shortfall')}: ${money(value.shortfall)}',
                          style: const TextStyle(color: Color(0xFFFFCCD0)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PouchCard(
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    key: const ValueKey('daily-budget-details'),
                    title: Text(t.text('budgetBreakdown')),
                    children: [
                      for (final entry in [
                        ('freeToSpend', value.remaining),
                        ('reservedExpenses', value.fundedExpenses),
                        ('protectedSavings', value.savings),
                      ])
                        PouchSummaryRow(
                          label: t.text(entry.$1),
                          value: money(entry.$2),
                        ),
                      const SizedBox(height: 8),
                      Text(t.text('savingsSetAsideHint')),
                      ExpansionTile(
                        title: Text(t.text('moreDetails')),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          for (final entry in [
                            ('spentOnDay', value.spent),
                            ('receivedIncome', value.income),
                            ('carry', value.carry),
                            ('unpaidObligations', value.reserved),
                          ])
                            PouchSummaryRow(
                              label: t.text(entry.$1),
                              value: money(entry.$2),
                            ),
                        ],
                      ),
                      if (value.daysRemaining > 0)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.text('periodEnds')),
                          subtitle: dateLabel(value.periodEnd),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        PurchasesScreen(
          embedded: true,
          bridge: widget.bridge,
          snapshot: widget.snapshot,
          strings: t,
          today: widget.today,
          selectedDate: widget.selectedDate,
          working: widget.working,
          run: widget.run,
          undo: widget.undo,
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: history,
            icon: const Icon(Icons.history_rounded),
            label: Text(t.text('purchaseHistory')),
          ),
        ),
        const SizedBox(height: 20),
        if (widget.selectedDate == widget.today) ...[
          FutureBuilder<PouchBudgetSummary>(
            key: ObjectKey(tomorrow),
            future: tomorrow,
            builder: (context, result) {
              if (!result.hasData || result.data!.daysRemaining == 0) {
                return const SizedBox.shrink();
              }
              return PouchCard(
                color: context.pouchPalette.surfaceWarm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.text('tomorrowForecast'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      money(result.data!.recommendation),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(t.text('tomorrowAssumption')),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
        if (widget.snapshot.planned.any(
          (item) => item.kind == 'expense' && item.status == 'pending',
        ))
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PouchSectionHeading(
                  title: t.text('upcomingCommitments'),
                  trailing: TextButton(
                    onPressed: widget.onOpenPlanned,
                    child: Text(t.text('viewAll')),
                  ),
                ),
                for (final item
                    in (widget.snapshot.planned
                            .where(
                              (item) =>
                                  item.kind == 'expense' &&
                                  item.status == 'pending',
                            )
                            .toList()
                          ..sort((a, b) => a.date.compareTo(b.date)))
                        .take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_note_outlined),
                    title: Text(item.description),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dateLabel(item.date),
                        Text(money(item.amount)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
