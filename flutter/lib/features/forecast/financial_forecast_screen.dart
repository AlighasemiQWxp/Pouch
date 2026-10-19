import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';
import '../../widgets/pouch_period_selector.dart';
import 'forecast_metric.dart';
import 'standard_forecast_section.dart';

class FinancialForecastScreen extends StatefulWidget {
  const FinancialForecastScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    required this.onOpenPlanned,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final VoidCallback onOpenPlanned;

  @override
  State<FinancialForecastScreen> createState() =>
      _FinancialForecastScreenState();
}

class _FinancialForecastScreenState extends State<FinancialForecastScreen> {
  String? _selectedId;
  String? _periodId;
  String? _standardSelectedId;
  PouchPeriodView? _periodView;
  int _periodRequest = 0;
  bool _incomeRequired = false;
  bool _countryExpanded = false;
  Future<_ForecastView>? _recorded;
  Future<_ForecastView>? _recommended;

  List<PouchPlannedItem> get _targets =>
      (_periodView?.targets ?? <PouchPlannedItem>[])
          .where((item) => item.amount > 0)
          .toList()
        ..sort((a, b) {
          final dateOrder = a.date.compareTo(b.date);
          if (dateOrder != 0) return dateOrder;
          return a.id.compareTo(b.id);
        });

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = PouchPeriodScope.maybeOf(context)?.periodId;
    if (shared != null && shared != _periodId) {
      _periodId = shared;
      _loadSelectedPeriod();
    }
  }

  @override
  void didUpdateWidget(covariant FinancialForecastScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot ||
        oldWidget.today != widget.today ||
        oldWidget.bridge != widget.bridge ||
        oldWidget.strings.language != widget.strings.language) {
      _refresh();
    }
  }

  void _refresh() {
    if (!widget.snapshot.periods.any((period) => period.id == _periodId)) {
      _periodId =
          widget.snapshot.currentPeriod?.id ??
          widget.snapshot.periods.lastOrNull?.id;
    }
    final standardTargets = widget.snapshot.planned.where(
      (item) => item.status == 'pending',
    );
    if (!standardTargets.any((item) => item.id == _standardSelectedId)) {
      _standardSelectedId = standardTargets.firstOrNull?.id;
    }
    _loadSelectedPeriod();
  }

  Future<void> _loadSelectedPeriod() async {
    final request = ++_periodRequest;
    final period = widget.snapshot.periods
        .where((item) => item.id == _periodId)
        .firstOrNull;
    _periodView = null;
    _recorded = null;
    _recommended = null;
    if (period == null) return;
    try {
      final view = await widget.bridge.periodView(period.start);
      if (!mounted || request != _periodRequest) return;
      setState(() {
        _periodView = view;
        if (!_targets.any((item) => item.id == _selectedId)) {
          _selectedId = _targets.firstOrNull?.id;
        }
        final id = _selectedId;
        if (id != null) {
          _recorded = _calculate(id, false);
          _recommended = _calculate(id, true);
        }
      });
    } catch (_) {
      if (mounted && request == _periodRequest) {
        setState(() => _periodView = null);
      }
    }
  }

  Future<_ForecastView> _calculate(String id, bool recommended) async {
    final bridge = widget.bridge;
    final calendar = widget.snapshot.preferences.calendar;
    final language = widget.strings.language;
    final value = await bridge.financialForecast(
      widget.today,
      id,
      recommended: recommended,
      incomeRequired: recommended && _incomeRequired,
      periodId: _periodId,
    );
    String? date;
    if (value.completionDate != null) {
      final (year, month, day) = await bridge.dateParts(
        value.completionDate!,
        calendar,
      );
      date = localizeDigits(
        '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}',
        language,
      );
    }
    return _ForecastView(value, date);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final targets = _targets;
    final id = _selectedId;
    final target = targets.where((item) => item.id == id).firstOrNull;
    final period = widget.snapshot.periods
        .where((item) => item.id == _periodId)
        .firstOrNull;
    final standardTargets = widget.snapshot.planned
        .where((item) => item.status == 'pending')
        .toList();
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('planningLabel'),
          title: strings.text('forecastTitle'),
          description: strings.text('forecastPageHint'),
        ),
        PouchPeriodSelector(
          periods: widget.snapshot.periods,
          selectedId: _periodId,
          strings: strings,
          label: strings.text('personalForecastPeriod'),
          onChanged: (id) {
            setState(() {
              _periodId = id;
              _loadSelectedPeriod();
            });
            PouchPeriodScope.maybeOf(context)?.onChanged(id);
          },
        ),
        const SizedBox(height: 16),
        if (period == null)
          PouchEmptyState(
            title: strings.text('chooseHorizon'),
            message: strings.text('forecastPeriodHint'),
          ),
        if (target == null)
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.text('forecastEmpty')),
                const SizedBox(height: 12),
                PouchPrimaryButton(
                  label: strings.text('forecastOpenPlanned'),
                  icon: Icons.event_note_rounded,
                  onPressed: widget.onOpenPlanned,
                ),
              ],
            ),
          )
        else ...[
          PouchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(id),
                  initialValue: id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: strings.text('forecastSelect'),
                  ),
                  items: targets
                      .map((item) {
                        return DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (value) => setState(() {
                    _selectedId = value;
                    if (value != null) {
                      _recorded = _calculate(value, false);
                      _recommended = _calculate(value, true);
                    }
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  target.description,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                FutureBuilder<_ForecastView>(
                  key: ObjectKey(_recorded),
                  future: _recorded,
                  builder: (context, result) {
                    if (!result.hasData) return const SizedBox.shrink();
                    return Text(
                      '${strings.text('forecastRemaining')}: '
                      '${_money(result.data!.value.remaining)}',
                    );
                  },
                ),
                PouchDateLabel(
                  bridge: widget.bridge,
                  strings: strings,
                  date: target.date,
                  calendar: widget.snapshot.preferences.calendar,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(false),
          const SizedBox(height: 14),
          PouchCard(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(strings.text('forecastExplore')),
              children: [_section(true)],
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (period != null)
          PouchCard(
            child: ExpansionTile(
              key: const ValueKey('forecast-budget-details'),
              tilePadding: EdgeInsets.zero,
              title: Text(strings.text('forecastBudgetDetails')),
              children: [
                PouchCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        children: [
                          PouchDateLabel(
                            bridge: widget.bridge,
                            strings: strings,
                            date: period.start,
                            calendar: widget.snapshot.preferences.calendar,
                          ),
                          PouchDateLabel(
                            bridge: widget.bridge,
                            strings: strings,
                            date: period.end,
                            calendar: widget.snapshot.preferences.calendar,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(strings.text('forecastPeriodHint')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PouchStatGrid(
                  children: [
                    PouchStat(
                      label: strings.text('receivedIncome'),
                      value: _money(period.income),
                    ),
                    PouchStat(
                      label: strings.text('freeToSpend'),
                      value: _money(period.remaining),
                    ),
                    PouchStat(
                      label: strings.text('reservedExpenses'),
                      value: _money(period.fundedExpenses),
                    ),
                    PouchStat(
                      label: strings.text('protectedSavings'),
                      value: _money(period.savings),
                    ),
                  ],
                ),
                if (period.status == 'closed' || period.status == 'expired')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: PouchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.text('historicalResults'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${strings.text('totalSpent')}: ${_money(period.expenses)}',
                          ),
                          Text(
                            '${strings.text('plannedSavings')}: ${_money(period.plannedSavings)}',
                          ),
                          Text(
                            '${strings.text('savedThisPeriod')}: ${_money(period.contributedSavings)}',
                          ),
                          Text(strings.text('historicalForecastHint')),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        const SizedBox(height: 16),
        PouchCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(strings.text('forecastCompareCountry')),
            onExpansionChanged: (expanded) =>
                setState(() => _countryExpanded = expanded),
            children: [
              if (standardTargets.isEmpty) Text(strings.text('forecastEmpty')),
              if (standardTargets.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(_standardSelectedId),
                  initialValue: _standardSelectedId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: strings.text('forecastSelect'),
                  ),
                  items: [
                    for (final item in standardTargets)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          item.description,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _standardSelectedId = value),
                ),
              if (_countryExpanded && _standardSelectedId != null)
                StandardForecastSection(
                  bridge: widget.bridge,
                  snapshot: widget.snapshot,
                  strings: strings,
                  today: widget.today,
                  selectedId: _standardSelectedId!,
                  run: widget.run,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(bool recommended) {
    final strings = widget.strings;
    var title = 'forecastRecorded';
    var hint = 'forecastRecordedQuestion';
    var future = _recorded;
    if (recommended) {
      title = 'forecastRecommended';
      hint = 'forecastRecommendationQuestion';
      future = _recommended;
    }
    return PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(title: strings.text(title)),
          const SizedBox(height: 8),
          Text(strings.text(hint)),
          const SizedBox(height: 12),
          if (recommended) ...[
            DropdownButtonFormField<bool>(
              initialValue: _incomeRequired,
              decoration: InputDecoration(
                labelText: strings.text('forecastImprovement'),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: false,
                  child: Text(
                    strings.text('forecastSpendLess'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text(
                    strings.text('forecastIncomeForDeadline'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _incomeRequired = value;
                  _recommended = _calculate(_selectedId!, true);
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          FutureBuilder<_ForecastView>(
            key: ObjectKey(future),
            future: future,
            builder: (context, result) {
              if (result.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (result.hasError || !result.hasData) {
                return PouchInlineError(strings.text('forecastError'));
              }
              return _results(result.data!, recommended);
            },
          ),
        ],
      ),
    );
  }

  Widget _results(_ForecastView view, bool recommended) {
    final value = view.value;
    final strings = widget.strings;
    final incomeRequired = recommended && _incomeRequired;
    final metrics = <Widget>[
      if (incomeRequired)
        _metric('forecastIncome', _optionalMoney(value.requiredIncome))
      else
        _metric('forecastRecordedIncome', _money(value.periodIncome)),
      _metric('forecastEssential', _money(value.essentialExpenses)),
      if (recommended)
        _metric('forecastControllable', _money(value.controllableSpending)),
      _metric('forecastLiving', _money(value.dailyAllowance)),
      if (!recommended)
        _metric('forecastConfiguredSavings', _money(value.configuredSavings)),
      _metric('forecastContribution', _money(value.contribution)),
    ];
    var completion = strings.text('forecastNoCapacity');
    if (view.date != null) {
      completion = strings.text('forecastDaysAndDate', {
        'days': localizeDigits('${value.completionDays}', strings.language),
        'date': view.date!,
      });
    }
    final target = _targets.where((item) => item.id == _selectedId).firstOrNull;
    var status = 'forecastNoCapacity';
    if (value.remaining == 0) {
      status = 'forecastFunded';
    } else if (value.overdue) {
      status = 'forecastOverdue';
    } else if (value.completionDate != null && target != null) {
      status = 'forecastBehind';
      if (value.completionDate!.compareTo(target.date) <= 0) {
        status = 'forecastOnTrack';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (incomeRequired)
          _metric('forecastIncome', _optionalMoney(value.requiredIncome)),
        ForecastMetric(
          label: strings.text('forecastCompletion'),
          value: completion,
          emphasized: true,
        ),
        if (value.extraDays != null && value.extraDays! > 0)
          _metric(
            'forecastExtraDays',
            localizeDigits('${value.extraDays}', strings.language),
          ),
        if (view.date != null || value.overdue) Text(strings.text(status)),
        if (recommended && value.fasterDays != null && value.fasterDays! > 0)
          Text(
            strings.text('forecastFaster', {
              'days': localizeDigits('${value.fasterDays}', strings.language),
            }),
          ),
        if (value.dailyAllowance == 0)
          Text(strings.text('forecastZeroAllowance')),
        if (recommended) Text(strings.text('forecastPreviewHint')),
        if (recommended && !incomeRequired)
          Text(strings.text('forecastSpendingPreview')),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(strings.text('forecastHowCalculated')),
          children: [
            ForecastMetricGrid(children: metrics),
            if (!recommended || incomeRequired)
              _metric(
                'forecastMonthlySaving',
                _optionalMoney(value.periodSaving),
              ),
            _metric('forecastAllocated', _money(value.allocated)),
            _metric('forecastRemaining', _money(value.remaining)),
            Text(strings.text('forecastSharedSavings')),
            Text(
              strings.text('forecastAssumptions', {
                'days': localizeDigits('${value.cycleDays}', strings.language),
              }),
            ),
          ],
        ),
      ],
    );
  }

  String _money(int amount) =>
      formatMoney(amount, widget.snapshot.preferences.currency, widget.strings);

  String _optionalMoney(int? amount) {
    if (amount == null) return widget.strings.text('forecastUnavailable');
    return _money(amount);
  }

  Widget _metric(String label, String value) =>
      ForecastMetric(label: widget.strings.text(label), value: value);
}

class _ForecastView {
  const _ForecastView(this.value, this.date);

  final PouchFinancialForecast value;
  final String? date;
}
