import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';
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
  bool _incomeRequired = false;
  Future<_ForecastView>? _recorded;
  Future<_ForecastView>? _recommended;

  List<PouchPlannedItem> get _targets =>
      widget.snapshot.planned
          .where((item) => item.status == 'pending' && item.amount > 0)
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
    final targets = _targets;
    if (!targets.any((item) => item.id == _selectedId)) {
      _selectedId = targets.firstOrNull?.id;
    }
    final id = _selectedId;
    if (id == null) {
      _recorded = null;
      _recommended = null;
      return;
    }
    _recorded = _calculate(id, false);
    _recommended = _calculate(id, true);
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
    return PouchPage(
      children: [
        PouchIntro(
          eyebrow: strings.text('planningLabel'),
          title: strings.text('forecastTitle'),
          description: strings.text('forecastPageHint'),
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
                        var kind = 'plannedExpenseType';
                        if (item.kind == 'goal') kind = 'savingsGoalType';
                        return DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.description} · ${strings.text(kind)} · ${_money(item.amount)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (value) => setState(() {
                    _selectedId = value;
                    _refresh();
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  target.description,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(_money(target.amount)),
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
          _section(true),
          const SizedBox(height: 14),
          PouchCard(
            child: StandardForecastSection(
              bridge: widget.bridge,
              snapshot: widget.snapshot,
              strings: strings,
              today: widget.today,
              selectedId: target.id,
              run: widget.run,
            ),
          ),
        ],
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
                labelText: strings.text('forecastIncomeBasis'),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: false,
                  child: Text(strings.text('forecastRecordedIncome')),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text(strings.text('forecastRequiredIncomeBasis')),
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
        _metric('forecastRecordedIncome', _money(value.monthlyIncome)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ForecastMetricGrid(children: metrics),
        const SizedBox(height: 8),
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
        if (!recommended || incomeRequired)
          _metric('forecastMonthlySaving', _optionalMoney(value.monthlySaving)),
        if (recommended && value.fasterDays != null && value.fasterDays! > 0)
          Text(
            strings.text('forecastFaster', {
              'days': localizeDigits('${value.fasterDays}', strings.language),
            }),
          ),
        if (value.overdue) Text(strings.text('forecastOverdue')),
        if (value.dailyAllowance == 0)
          Text(strings.text('forecastZeroAllowance')),
        if (recommended) Text(strings.text('forecastPreviewHint')),
        if (recommended && !incomeRequired)
          Text(strings.text('forecastSpendingPreview')),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(strings.text('forecastHowCalculated')),
          children: [
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
