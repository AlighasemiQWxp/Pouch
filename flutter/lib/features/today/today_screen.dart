import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.selectedDate,
    required this.working,
    required this.onDateChanged,
    required this.run,
    required this.undo,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final String selectedDate;
  final bool working;
  final ValueChanged<String> onDateChanged;
  final PouchMutation run;
  final PouchUndo undo;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<PouchBudgetSummary> _summary = widget.bridge.budgetSummary(
    widget.selectedDate,
  );

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.snapshot.revision != widget.snapshot.revision) {
      _summary = widget.bridge.budgetSummary(widget.selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final plannedForDay = widget.snapshot.planned
        .where(
          (item) => item.date == widget.selectedDate && item.kind == 'expense',
        )
        .toList(growable: false);
    final isFuture = widget.selectedDate.compareTo(widget.today) > 0;
    return PouchPage(
      children: [
        _buildDateBar(context),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: _showHistory,
            icon: const Icon(Icons.history_rounded),
            label: Text(strings.text('purchaseHistory')),
          ),
        ),
        const SizedBox(height: 14),
        FutureBuilder<PouchBudgetSummary>(
          future: _summary,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return PouchCard(
                child: PouchInlineError(strings.text('invalidDate')),
              );
            }
            if (!snapshot.hasData) {
              return const PouchCard(
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _buildSummary(snapshot.data!);
          },
        ),
        const SizedBox(height: 14),
        if (widget.selectedDate == widget.today) _buildTomorrowForecast(),
        if (plannedForDay.isNotEmpty) _buildPlannedExpenses(plannedForDay),
        _PurchaseForm(
          bridge: widget.bridge,
          snapshot: widget.snapshot,
          strings: strings,
          date: widget.selectedDate,
          future: isFuture,
          run: widget.run,
        ),
      ],
    );
  }

  Widget _buildDateBar(BuildContext context) {
    final strings = widget.strings;
    final startDate = DateTime.parse(widget.snapshot.startDate);
    final selected = DateTime.parse(widget.selectedDate);
    final dateLabel = FutureBuilder<String>(
      future: _formatDate(widget.selectedDate),
      builder: (context, snapshot) => Text(
        snapshot.data ?? widget.selectedDate,
        textAlign: TextAlign.end,
        style: TextStyle(
          color: context.pouchPalette.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return PouchCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('dailySnapshot').toUpperCase(),
            style: TextStyle(
              color: context.pouchPalette.gold,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              PouchIconButton(
                label: strings.text('previous'),
                icon: Icons.chevron_left_rounded,
                onPressed: selected.isAfter(startDate)
                    ? () => _stepDate(-1)
                    : null,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showPouchDatePicker(
                      context: context,
                      bridge: widget.bridge,
                      strings: strings,
                      initialDate: widget.selectedDate,
                      calendar: widget.snapshot.preferences.calendar,
                      weekStart: widget.snapshot.preferences.weekStart,
                      firstDate: widget.snapshot.startDate,
                      lastDate: '9998-12-31',
                      highlightedDates: {
                        for (final record in widget.snapshot.days)
                          if (record.purchases.isNotEmpty) record.date,
                        for (final item in widget.snapshot.planned)
                          if (item.kind == 'expense') item.date,
                      },
                    );
                    if (picked == null) return;
                    widget.onDateChanged(picked);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 11,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 19,
                          color: context.pouchPalette.goldDeep,
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: dateLabel),
                      ],
                    ),
                  ),
                ),
              ),
              PouchIconButton(
                label: strings.text('next'),
                icon: Icons.chevron_right_rounded,
                onPressed: () => _stepDate(1),
              ),
              TextButton(
                onPressed: () => widget.onDateChanged(widget.today),
                child: Text(strings.text('today')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String> _formatDate(String date) async {
    if (widget.snapshot.preferences.calendar == 'gregory') {
      return formatGregorianDate(date, widget.strings.language);
    }
    final parts = await widget.bridge.dateParts(date, 'persian');
    return formatJalaliDate(
      parts.$1,
      parts.$2,
      parts.$3,
      widget.strings.language,
    );
  }

  void _stepDate(int count) {
    final next = DateTime.parse('${widget.selectedDate}T00:00:00Z')
        .add(Duration(days: count));
    widget.onDateChanged(_iso(next));
  }

  Widget _buildSummary(PouchBudgetSummary summary) {
    final strings = widget.strings;
    final isPast = widget.selectedDate.compareTo(widget.today) < 0;
    var headline = strings.text('recommended');
    var headlineAmount = summary.recommendation;
    var headlineHint = strings.text('recommendationHint');
    if (isPast) {
      headline = strings.text('balance');
      headlineAmount = summary.remaining;
      headlineHint = strings.text('historyHint');
    } else if (widget.selectedDate.compareTo(widget.today) > 0) {
      headlineHint = strings.text('futureHint');
    }
    return _ScreenScope(
      snapshot: widget.snapshot,
      strings: strings,
      child: Column(
        children: [
          PouchCard(
            color: context.pouchPalette.ink,
            padding: const EdgeInsets.fromLTRB(23, 21, 23, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  headline.toUpperCase(),
                  style: TextStyle(
                    color: context.pouchPalette.goldPale,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 9),
                FittedBox(
                  alignment: AlignmentDirectional.centerStart,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(
                      headlineAmount,
                      widget.snapshot.preferences.currency,
                      strings,
                    ),
                    style: TextStyle(
                      color: Color(0xFFFFF8E8),
                      fontFamily: 'serif',
                      fontSize: 39,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  headlineHint,
                  style: TextStyle(
                    color: Color(0xFFD2C4A8),
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 17),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 7,
                  children: [
                    Text(
                      strings.text('periodEnds'),
                      style: TextStyle(color: Color(0xFFD2C4A8), fontSize: 12),
                    ),
                    FutureBuilder<String>(
                      future: _formatDate(summary.periodEnd),
                      builder: (context, value) => Text(
                        value.data ?? summary.periodEnd,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (summary.shortfall > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.text('shortfall', {
                      'amount': formatMoney(
                        summary.shortfall,
                        widget.snapshot.preferences.currency,
                        strings,
                      ),
                    }),
                    style: TextStyle(
                      color: context.pouchPalette.goldPale,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          PouchCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: Text(
                strings.text('todayBreakdown'),
                style: TextStyle(
                  color: context.pouchPalette.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                _AmountRow(
                  label: strings.text('incomeAvailable'),
                  amount: summary.income,
                ),
                _AmountRow(
                  label: strings.text('requiredExpenses'),
                  amount: summary.requiredExpenses,
                ),
                _AmountRow(
                  label: strings.text('monthlySavings'),
                  amount: summary.savings,
                ),
                _AmountRow(
                  label: strings.text('upcoming'),
                  amount: summary.reserved,
                ),
                _AmountRow(
                  label: strings.text('spentToday'),
                  amount: summary.spent,
                ),
                _AmountRow(label: strings.text('base'), amount: summary.daily),
                _AmountRow(label: strings.text('carry'), amount: summary.carry),
                const Divider(height: 20),
                _AmountRow(
                  label: strings.text('balance'),
                  amount: summary.remaining,
                  bold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTomorrowForecast() {
    final tomorrow = DateTime.parse('${widget.today}T00:00:00Z')
        .add(const Duration(days: 1));
    final date = _iso(tomorrow);
    return FutureBuilder<PouchBudgetSummary>(
      future: widget.bridge.budgetSummary(date),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PouchCard(
            color: context.pouchPalette.surfaceWarm,
            child: Row(
              children: [
                Icon(
                  Icons.wb_twilight_rounded,
                  color: context.pouchPalette.goldDeep,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.strings.text('tomorrowForecast'),
                    style: TextStyle(
                      color: context.pouchPalette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  formatMoney(
                    snapshot.data!.carry,
                    widget.snapshot.preferences.currency,
                    widget.strings,
                  ),
                  style: TextStyle(
                    color: context.pouchPalette.goldDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlannedExpenses(List<PouchPlannedItem> items) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(
            title: widget.strings.text('plannedForDay'),
            trailing: Text(
              localizeDigits('${items.length}', widget.strings.language),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.strings.text(item.category)} · ${widget.strings.text(item.status)}',
                          style: TextStyle(
                            color: context.pouchPalette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(
                      item.amount,
                      widget.snapshot.preferences.currency,
                      widget.strings,
                    ),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _showHistory() async {
    final purchases =
        widget.snapshot.day(widget.selectedDate)?.purchases ?? const [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.text('purchaseHistory')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (purchases.isEmpty) Text(widget.strings.text('noPurchases')),
                for (final purchase in purchases)
                  _PurchaseTile(
                    purchase: purchase,
                    currency: widget.snapshot.preferences.currency,
                    strings: widget.strings,
                    onEdit: () {
                      Navigator.pop(dialogContext);
                      _editPurchase(purchase);
                    },
                    onDelete: () {
                      Navigator.pop(dialogContext);
                      _deletePurchase(purchase);
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(widget.strings.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _editPurchase(PouchPurchase purchase) async {
    final result = await showDialog<_PurchaseValues>(
      context: context,
      builder: (context) => _PurchaseDialog(
        strings: widget.strings,
        initialDescription: purchase.description,
        initialAmount: amountInput(
          purchase.amount,
          language: widget.strings.language,
        ),
        initialCategory: purchase.category,
      ),
    );
    if (result == null) return;
    await widget.run(
      () => widget.bridge.editPurchase(
        date: widget.selectedDate,
        id: purchase.id,
        description: result.description,
        amount: result.amount,
        category: result.category,
      ),
    );
  }

  Future<void> _deletePurchase(PouchPurchase purchase) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('deletePurchase')),
        content: Text(purchase.description),
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
    final accepted = await widget.run(
      () => widget.bridge.removePurchase(widget.selectedDate, purchase.id),
    );
    if (accepted && mounted) {
      showPouchUndoMessage(context, widget.strings, 'deleted', widget.undo);
    }
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final int amount;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: bold
                  ? context.pouchPalette.ink
                  : context.pouchPalette.muted,
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          formatMoney(
            amount,
            _ScreenScope.of(context).snapshot.preferences.currency,
            _ScreenScope.of(context).strings,
          ),
          style: TextStyle(
            color: bold
                ? context.pouchPalette.goldDeep
                : context.pouchPalette.ink,
            fontSize: 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ScreenScope extends InheritedWidget {
  const _ScreenScope({
    required this.snapshot,
    required this.strings,
    required super.child,
  });

  final PouchSnapshot snapshot;
  final AppStrings strings;

  static _ScreenScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScreenScope>()!;

  @override
  bool updateShouldNotify(_ScreenScope oldWidget) =>
      snapshot.revision != oldWidget.snapshot.revision ||
      strings.language != oldWidget.strings.language;
}

class _PurchaseForm extends StatefulWidget {
  const _PurchaseForm({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.date,
    required this.future,
    required this.run,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String date;
  final bool future;
  final PouchMutation run;

  @override
  State<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<_PurchaseForm> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'other';

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(title: widget.strings.text('addPurchase')),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: widget.strings.text('description'),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final amount = TextField(
                controller: _amount,
                inputFormatters: [
                  PouchMoneyInputFormatter(widget.strings.language),
                ],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.strings.text('amount'),
                ),
              );
              final category = DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: widget.strings.text('category'),
                ),
                items: _categories()
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(widget.strings.text(value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) =>
                    setState(() => _category = value ?? 'other'),
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  children: [amount, const SizedBox(height: 10), category],
                );
              }
              return Row(
                children: [
                  Expanded(child: amount),
                  const SizedBox(width: 12),
                  Expanded(child: category),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PouchPrimaryButton(
              label: widget.strings.text('savePurchase'),
              icon: Icons.add_rounded,
              onPressed: () async {
                final id = _newId();
                final description = _description.text.trim();
                final amountText = _amount.text.trim();
                final saved = await widget.run(() {
                  if (widget.future) {
                    return widget.bridge.savePlanned(
                      id: id,
                      description: description,
                      amount: amountText,
                      category: _category,
                      kind: 'expense',
                      date: widget.date,
                    );
                  }
                  return widget.bridge.addPurchase(
                    id: id,
                    date: widget.date,
                    description: description,
                    amount: amountText,
                    category: _category,
                  );
                });
                if (saved && context.mounted) {
                  _description.clear();
                  _amount.clear();
                  setState(() => _category = 'other');
                  var message = 'saved';
                  if (widget.future) message = 'plannedFuture';
                  showPouchMessage(context, widget.strings, message);
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.purchase,
    required this.currency,
    required this.strings,
    required this.onEdit,
    required this.onDelete,
  });

  final PouchPurchase purchase;
  final String currency;
  final AppStrings strings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    var categoryLabel = strings.text(purchase.category);
    if (purchase.fundedByGoal) categoryLabel = strings.text('goalPurchase');
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsetsDirectional.only(
        start: 12,
        end: 5,
        top: 7,
        bottom: 7,
      ),
      decoration: BoxDecoration(
        color: context.pouchPalette.surface,
        border: Border.all(color: context.pouchPalette.border),
        borderRadius: BorderRadius.circular(13),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bullet = Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: context.pouchPalette.goldBright,
              shape: BoxShape.circle,
            ),
          );
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                purchase.description,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                categoryLabel,
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  fontSize: 11,
                ),
              ),
            ],
          );
          final amount = Text(
            formatMoney(purchase.amount, currency, strings),
            style: TextStyle(fontWeight: FontWeight.w700),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    bullet,
                    const SizedBox(width: 10),
                    Expanded(child: description),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [amount, actions],
                ),
              ],
            );
          }
          return Row(
            children: [
              bullet,
              const SizedBox(width: 10),
              Expanded(child: description),
              amount,
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({
    required this.strings,
    required this.initialDescription,
    required this.initialAmount,
    required this.initialCategory,
  });

  final AppStrings strings;
  final String initialDescription;
  final String initialAmount;
  final String initialCategory;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late final _description = TextEditingController(
    text: widget.initialDescription,
  );
  late final _amount = TextEditingController(text: widget.initialAmount);
  late String _category = widget.initialCategory;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.text('editPurchase')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _description,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: widget.strings.text('description'),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          inputFormatters: [PouchMoneyInputFormatter(widget.strings.language)],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.strings.text('amount')),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: InputDecoration(
            labelText: widget.strings.text('category'),
          ),
          items: _categories()
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(widget.strings.text(value)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) => setState(() => _category = value ?? 'other'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _PurchaseValues(_description.text, _amount.text, _category),
        ),
        child: Text(widget.strings.text('save')),
      ),
    ],
  );
}

class _PurchaseValues {
  const _PurchaseValues(this.description, this.amount, this.category);

  final String description;
  final String amount;
  final String category;
}

List<String> _categories() => const [
  'other',
  'food',
  'transport',
  'shopping',
  'health',
  'entertainment',
  'bills',
];

String _iso(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
