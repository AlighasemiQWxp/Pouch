import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import 'dashboard_charts.dart';
import 'dashboard_filters.dart';
import 'dashboard_models.dart';
import 'dashboard_progress.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.onOpenToday,
    required this.onOpenBudget,
    required this.onOpenPlans,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final VoidCallback onOpenToday, onOpenBudget, onOpenPlans;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DashboardSelection _selection;
  DashboardData? _data;
  bool _loading = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _selection = _defaultSelection();
    _load();
  }

  DashboardSelection _defaultSelection() {
    final periodId = widget.snapshot.currentPeriod?.id;
    var mode = 'monthly';
    if (periodId != null) mode = 'period';
    return DashboardSelection(
      mode: mode,
      anchor: widget.today,
      from: widget.today,
      through: widget.today,
      periodId: periodId,
    );
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot ||
        oldWidget.today != widget.today ||
        oldWidget.bridge != widget.bridge ||
        oldWidget.strings.language != widget.strings.language) {
      if (_selection.periodId != null &&
          !widget.snapshot.periods.any(
            (period) => period.id == _selection.periodId,
          )) {
        if (_selection.mode == 'period') {
          _selection = _defaultSelection();
        } else {
          _selection = DashboardSelection(
            mode: _selection.mode,
            anchor: _selection.anchor,
            from: _selection.from,
            through: _selection.through,
            periodId: widget.snapshot.currentPeriod?.id,
          );
        }
      }
      _load();
    }
  }

  bool get _needsPeriod =>
      _selection.mode == 'period' && _selection.periodId == null;

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = !_needsPeriod;
      _failed = false;
      _data = null;
    });
    if (_needsPeriod) return;
    try {
      final data = await widget.bridge.dashboard(_selection);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _text(String key) => widget.strings.text(key);
  String _money(int value) =>
      formatMoney(value, widget.snapshot.preferences.currency, widget.strings);

  @override
  Widget build(BuildContext context) => PouchPage(
    children: [
      PouchIntro(
        eyebrow: _text('insightsLabel'),
        title: _text('dashboardTitle'),
        description: _text('dashboardIntro'),
      ),
      DashboardFilters(
        selection: _selection,
        today: widget.today,
        snapshot: widget.snapshot,
        bridge: widget.bridge,
        strings: widget.strings,
        onChanged: (selection) {
          _selection = selection;
          _load();
        },
      ),
      const SizedBox(height: 16),
      if (widget.snapshot.currentPeriod == null &&
          _selection.mode == 'monthly' &&
          _selection.anchor == widget.today) ...[
        Semantics(
          liveRegion: true,
          child: PouchCard(child: Text(_text('dashboardNoActivePeriod'))),
        ),
        const SizedBox(height: 16),
      ],
      if (_needsPeriod)
        PouchCard(child: Text(_text('dashboardChoosePeriodHint'))),
      if (_loading)
        Semantics(
          label: _text('dashboardLoading'),
          liveRegion: true,
          child: const PouchCard(child: LinearProgressIndicator()),
        ),
      if (_failed)
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchInlineError(_text('dashboardError')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_text('dashboardRetry')),
              ),
            ],
          ),
        ),
      if (_data case final data?) ..._content(data),
    ],
  );

  List<Widget> _content(DashboardData data) {
    final strings = widget.strings;
    final currency = widget.snapshot.preferences.currency;
    final labels = data.points
        .map((point) => point.rangeLabel)
        .toList(growable: false);
    final periodLabels = data.comparisons
        .map((period) => period.rangeLabel)
        .toList(growable: false);
    if (data.futureOnly) {
      return [
        _range(data),
        const SizedBox(height: 16),
        PouchEmptyState(
          title: _text('dashboardFuture'),
          message: _text('dashboardFutureHint'),
        ),
      ];
    }
    return [
      _range(data),
      const SizedBox(height: 16),
      _pair([
        _balance(data),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSectionHeading(title: _text('dashboardCashFlow')),
              const SizedBox(height: 8),
              _summary('receivedIncome', data.income),
              _summary('totalSpent', data.expenses),
              const Divider(),
              _summary('dashboardNet', data.net),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('dashboard-open-today'),
            onPressed: widget.onOpenToday,
            icon: const Icon(Icons.today_outlined),
            label: Text(_text('dashboardOpenToday')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('dashboard-open-budget'),
            onPressed: widget.onOpenBudget,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text(_text('dashboardOpenBudget')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('dashboard-open-plans'),
            onPressed: widget.onOpenPlans,
            icon: const Icon(Icons.event_note_outlined),
            label: Text(_text('dashboardOpenPlans')),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (!data.hasActivity)
        PouchEmptyState(
          title: _text('dashboardEmpty'),
          message: _text('dashboardEmptyHint'),
        )
      else if (data.categories.isNotEmpty)
        DashboardDonut(
          title: _text('dashboardCategories'),
          hint: _text('dashboardCategoryHint'),
          values: data.categories,
          strings: strings,
          currency: currency,
        )
      else
        PouchCard(child: Text(_text('dashboardNoSpending'))),
      const SizedBox(height: 24),
      _heading('dashboardMoreDetails'),
      _details(
        id: 'activity',
        title: 'dashboardActivityDetails',
        hint: 'dashboardActivityDetailsHint',
        icon: Icons.bar_chart_outlined,
        content: () => [
          if (data.assignedIncome case final assigned?) ...[
            PouchCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _summary('dashboardAssignedIncome', assigned),
                  Text(_text('dashboardAssignmentHint')),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          DashboardChart(
            title: _text('dashboardIncomeExpenses'),
            hint: _text('dashboardFlowHint'),
            labels: labels,
            strings: strings,
            currency: currency,
            series: [
              DashboardSeries(
                _text('receivedIncome'),
                data.points.map((p) => p.income).toList(),
              ),
              DashboardSeries(
                _text('totalSpent'),
                data.points.map((p) => p.expenses).toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DashboardDonut(
            title: _text('dashboardEssential'),
            hint: _text('dashboardEssentialHint'),
            values: data.spending,
            strings: strings,
            currency: currency,
          ),
        ],
      ),
      _details(
        id: 'balances',
        title: 'dashboardBalanceDetails',
        hint: 'dashboardBalanceDetailsHint',
        icon: Icons.account_balance_wallet_outlined,
        content: () => [
          Text(_text('dashboardPositionHint')),
          const SizedBox(height: 12),
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary('dashboardCash', data.cash),
                _summary('protectedSavings', data.protectedSavings),
                _summary('dashboardUnpaid', data.reserved),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DashboardDonut(
            title: _text('dashboardAllocation'),
            hint: _text('dashboardAllocationHint'),
            values: data.allocation,
            strings: strings,
            currency: currency,
          ),
          const SizedBox(height: 16),
          DashboardChart(
            title: _text('dashboardBalances'),
            hint: _text('dashboardBalanceHint'),
            labels: labels,
            strings: strings,
            currency: currency,
            line: true,
            steps: true,
            series: [
              DashboardSeries(
                _text('dashboardCash'),
                data.points.map((p) => p.cash).toList(),
              ),
              DashboardSeries(
                _text('dashboardRecordedSavings'),
                data.points.map((p) => p.savings).toList(),
              ),
            ],
          ),
        ],
      ),
      _details(
        id: 'budget',
        title: 'dashboardBudgetProgress',
        hint: 'dashboardBudgetDetailsHint',
        icon: Icons.receipt_long_outlined,
        content: () => [
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_text('dashboardBudgetHint')),
                const SizedBox(height: 16),
                DashboardProgress(
                  values: data.progress,
                  strings: strings,
                  currency: currency,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _pair([
            DashboardChart(
              title: _text('dashboardCompare'),
              hint: _text('dashboardCompareHint'),
              labels: periodLabels,
              strings: strings,
              currency: currency,
              series: [
                DashboardSeries(
                  _text('receivedIncome'),
                  data.comparisons.map((p) => p.income).toList(),
                ),
                DashboardSeries(
                  _text('totalSpent'),
                  data.comparisons.map((p) => p.expenses).toList(),
                ),
              ],
            ),
            DashboardChart(
              title: _text('dashboardPlannedActual'),
              hint: _text('dashboardPlannedHint'),
              labels: periodLabels,
              strings: strings,
              currency: currency,
              series: [
                DashboardSeries(
                  _text('dashboardPlanned'),
                  data.comparisons.map((p) => p.planned).toList(),
                ),
                DashboardSeries(
                  _text('dashboardPaid'),
                  data.comparisons.map((p) => p.paid).toList(),
                ),
              ],
            ),
          ]),
          if (data.comparisonCount > data.comparisons.length)
            Text(
              strings.text('dashboardComparisonLimit', {
                'count': localizeDigits(
                  '${data.comparisonCount}',
                  strings.language,
                ),
              }),
            ),
        ],
      ),
      _details(
        id: 'savings',
        title: 'dashboardSavingsDetails',
        hint: 'dashboardSavingsDetailsHint',
        icon: Icons.savings_outlined,
        content: () => [
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PouchSectionHeading(title: _text('dashboardGoals')),
                const SizedBox(height: 8),
                Text(_text('dashboardGoalsHint')),
                const SizedBox(height: 16),
                if (data.goals.isEmpty) Text(_text('dashboardNoGoals')),
                DashboardProgress(
                  values: data.goals,
                  strings: strings,
                  currency: currency,
                ),
                if (data.goalCount > data.goals.length)
                  Text(
                    strings.text('dashboardGoalLimit', {
                      'count': localizeDigits(
                        '${data.goalCount}',
                        strings.language,
                      ),
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary('dashboardContributions', data.contributions),
                _summary('dashboardReleases', data.releases),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _pair([
            DashboardChart(
              title: _text('dashboardSavingsMovements'),
              hint: _text('dashboardSavingsHint'),
              labels: labels,
              strings: strings,
              currency: currency,
              series: [
                DashboardSeries(
                  _text('dashboardContributions'),
                  data.points.map((p) => p.contributions).toList(),
                ),
                DashboardSeries(
                  _text('dashboardReleases'),
                  data.points.map((p) => p.releases).toList(),
                ),
              ],
            ),
            DashboardChart(
              title: _text('dashboardSavingsPlan'),
              hint: _text('dashboardSavingsPlanHint'),
              labels: periodLabels,
              strings: strings,
              currency: currency,
              series: [
                DashboardSeries(
                  _text('dashboardSavingsMinimum'),
                  data.comparisons.map((p) => p.savingsTarget).toList(),
                ),
                DashboardSeries(
                  _text('dashboardNetAllocations'),
                  data.comparisons.map((p) => p.savings).toList(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ];
  }

  Widget _range(DashboardData data) => Semantics(
    liveRegion: true,
    child: Text(
      widget.strings.text('dashboardRange', {
        'from': localizeDigits(data.fromLabel, widget.strings.language),
        'through': localizeDigits(data.throughLabel, widget.strings.language),
      }),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );

  Widget _balance(DashboardData data) {
    final palette = context.pouchPalette;
    var label = _text('dashboardFree');
    var color = palette.goldDeep;
    var hint = _text('dashboardFreeHint');
    if (data.free < 0) {
      label = _text('dashboardShortfall');
      color = palette.danger;
      hint = _text('dashboardDeficitHint');
    }
    return PouchCard(
      key: const ValueKey('dashboard-balance'),
      color: palette.selection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _money(data.free),
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(hint),
          const SizedBox(height: 12),
          Text(
            widget.strings.text('dashboardAsOf', {
              'date': localizeDigits(data.asOfLabel, widget.strings.language),
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _details({
    required String id,
    required String title,
    required String hint,
    required IconData icon,
    required List<Widget> Function() content,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: PouchCard(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ExpansionTile(
        key: ValueKey('dashboard-details-$id'),
        title: Text(_text(title)),
        subtitle: Text(_text(hint)),
        leading: Icon(icon),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content(),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _summary(String key, int amount) =>
      PouchSummaryRow(label: _text(key), value: _money(amount));

  Widget _pair(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      var width = constraints.maxWidth;
      if (width >= 840 && MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
        width = (width - 16) / 2;
      }
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );

  Widget _heading(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: PouchSectionHeading(title: _text(key)),
  );
}
