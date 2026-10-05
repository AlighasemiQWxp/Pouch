import 'package:flutter/material.dart';

import 'forecast_metric.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../widgets/pouch_widgets.dart';

class StandardForecastSection extends StatefulWidget {
  const StandardForecastSection({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.selectedId,
    required this.run,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final String selectedId;
  final PouchMutation run;

  @override
  State<StandardForecastSection> createState() =>
      _StandardForecastSectionState();
}

class _StandardForecastSectionState extends State<StandardForecastSection> {
  List<PouchEconomicCountry> _countries = [];
  String _country = '';
  PouchStandardForecast? _forecast;
  Future<String>? _date;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _request = 0;

  String _defaultCountry() => switch (widget.snapshot.preferences.country) {
    'canada' => 'CA',
    'iran' => 'IR',
    'united_states' => 'US',
    'united_kingdom' => 'GB',
    'germany' => 'DE',
    'australia' => 'AU',
    'new_zealand' => 'NZ',
    _ => '',
  };

  @override
  void initState() {
    super.initState();
    _country = _defaultCountry();
    _load();
  }

  @override
  void didUpdateWidget(covariant StandardForecastSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.preferences.country !=
        widget.snapshot.preferences.country) {
      _country = _defaultCountry();
    }
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.today != widget.today ||
        oldWidget.snapshot.revision != widget.snapshot.revision ||
        oldWidget.snapshot.preferences.calendar !=
            widget.snapshot.preferences.calendar ||
        oldWidget.strings.language != widget.strings.language ||
        oldWidget.bridge != widget.bridge ||
        oldWidget.snapshot.preferences.country !=
            widget.snapshot.preferences.country) {
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    final request = ++_request;
    final country = _country;
    setState(() {
      _loading = true;
      _refreshing = false;
      _error = null;
      if (!force) {
        _forecast = null;
        _date = null;
      }
    });
    try {
      final countries = await widget.bridge.economicCountries();
      if (!mounted || request != _request) return;
      setState(() {
        _countries = countries;
      });
      if (country.isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }
      var value = await widget.bridge.standardForecast(
        widget.today,
        widget.selectedId,
        country,
      );
      if (!mounted || request != _request) return;
      _show(value);
      final automatic = countries.any(
        (item) => item.code == country && item.automatic,
      );
      if (automatic && (force || value.needsRefresh)) {
        setState(() {
          _refreshing = true;
        });
        try {
          await widget.bridge.refreshEconomicProfile(
            country,
            widget.snapshot.preferences.currency,
          );
          if (!mounted || request != _request) return;
          value = await widget.bridge.standardForecast(
            widget.today,
            widget.selectedId,
            country,
          );
          if (!mounted || request != _request) return;
          _show(value);
        } catch (error) {
          if (mounted && request == _request) {
            setState(() {
              _error = 'standardRefreshFailed';
              if (error.toString().contains('review_required')) {
                _error = 'standardReviewRequired';
              }
              if (error.toString().contains('iran_source_unavailable')) {
                _error = 'standardIranUnavailable';
              }
              if (error.toString().contains('iran_format_changed')) {
                _error = 'standardIranFormat';
              }
              for (final entry in {
                'iran_tls_failed': 'standardIranTls',
                'iran_transport_failed': 'standardIranTransport',
                'iran_timeout': 'standardIranTimeout',
                'iran_http_status:': 'standardIranHttp',
                'iran_body_failed': 'standardIranBody',
                'iran_body_too_large': 'standardIranBodyTooLarge',
                'iran_cache_failed': 'standardIranCache',
                'iran_redirect_failed': 'standardIranRedirect',
                'iran_year_changed': 'standardIranYear',
                'iran_unit_changed': 'standardIranUnit',
                'iran_validation_failed': 'standardIranValidation',
              }.entries) {
                if (error.toString().contains(entry.key)) _error = entry.value;
              }
              if (error.toString().contains('cache_save_failed')) {
                _error = 'standardCacheSaveFailed';
              }
            });
          }
        } finally {
          if (mounted && request == _request) {
            setState(() {
              _refreshing = false;
            });
          }
        }
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'standardError';
        });
      }
    }
  }

  void _show(PouchStandardForecast value) {
    setState(() {
      _forecast = value;
      _loading = false;
      _date = null;
      if (value.completionDate != null) {
        _date = _formatDate(value.completionDate!);
      }
    });
  }

  Future<String> _formatDate(String iso) async {
    final (year, month, day) = await widget.bridge.dateParts(
      iso,
      widget.snapshot.preferences.calendar,
    );
    return localizeDigits(
      '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}',
      widget.strings.language,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final value = _forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PouchSectionHeading(title: strings.text('standardTitle')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('$_country:${_countries.length}'),
          initialValue: _countries.any((item) => item.code == _country)
              ? _country
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: strings.text('standardCountry'),
          ),
          items: _countries
              .map(
                (item) => DropdownMenuItem(
                  value: item.code,
                  child: Text(strings.text(item.labelKey)),
                ),
              )
              .toList(),
          onChanged: (country) {
            if (country == null) return;
            _country = country;
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _country.isEmpty)
          Text(strings.text('standardSelectCountry')),
        if (_refreshing) ...[
          const LinearProgressIndicator(),
          Text(strings.text('standardRefreshing')),
        ],
        if (_error != null) PouchInlineError(strings.text(_error!)),
        if (value != null) ..._results(value),
        if (_country.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              if (_countries.any(
                (item) => item.code == _country && item.automatic,
              ))
                TextButton.icon(
                  onPressed: _refreshing ? null : () => _load(force: true),
                  icon: const Icon(Icons.refresh),
                  label: Text(strings.text('standardRefresh')),
                ),
              TextButton.icon(
                onPressed: _loading ? null : _customize,
                icon: const Icon(Icons.tune),
                label: Text(strings.text('standardCustomize')),
              ),
              if (value?.customized == true)
                TextButton(
                  onPressed: () async {
                    final saved = await widget.run(
                      () => widget.bridge.resetEconomicProfile(_country),
                    );
                    if (saved && mounted) await _load();
                  },
                  child: Text(strings.text('standardUseAutomatic')),
                ),
            ],
          ),
      ],
    );
  }

  List<Widget> _results(PouchStandardForecast value) {
    final strings = widget.strings;
    String money(int amount) => formatMoney(amount, value.currency, strings);
    String optional(int? amount) {
      if (amount == null) return strings.text('forecastUnavailable');
      return money(amount);
    }

    final widgets = <Widget>[];
    if (value.country == 'IR' && !value.customized) {
      widgets.add(Text(strings.text('standardHouseholdScenario')));
    }
    if (value.customized) {
      widgets.add(Text(strings.text('standardCustomAssumptions')));
    }
    if (value.monthlyNetIncome == null) {
      widgets.add(Text(strings.text('standardInitialConnection')));
    } else {
      widgets.addAll([
        ForecastMetricGrid(
          children: [
            _metric(
              'standardConvertedGoal',
              optional(value.convertedRemaining),
            ),
            _metric(
              value.country == 'IR' && !value.customized
                  ? 'standardHouseholdIncome'
                  : 'standardNetIncome',
              optional(value.monthlyNetIncome),
            ),
            _metric('standardCapacity', optional(value.monthlySaving)),
          ],
        ),
      ]);
      if (_date != null) {
        widgets.add(
          FutureBuilder<String>(
            future: _date,
            builder: (context, date) {
              if (date.hasError) {
                return PouchInlineError(strings.text('standardError'));
              }
              if (!date.hasData) {
                return const LinearProgressIndicator();
              }
              return ForecastMetric(
                emphasized: true,
                label: strings.text('forecastCompletion'),
                value: strings.text('forecastDaysAndDate', {
                  'days': localizeDigits(
                    '${value.completionDays}',
                    strings.language,
                  ),
                  'date': date.data!,
                }),
              );
            },
          ),
        );
      } else {
        var reason = 'forecastNoCapacity';
        if (value.status == 'conversion_required') {
          reason = 'standardConversionRequired';
        }
        widgets.add(_metric('forecastCompletion', strings.text(reason)));
      }
    }
    if (value.cacheWarning) {
      widgets.add(Text(strings.text('standardCacheWarning')));
    }
    if (value.needsRefresh && value.downloaded != null) {
      widgets.add(Text(strings.text('standardOlderCache')));
    }
    widgets.add(
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(strings.text('standardSources')),
        children: [
          _metric('standardFullGoal', optional(value.convertedGoal)),
          _metric(
            'standardRequiredSaving',
            optional(value.requiredMonthlySaving),
          ),
          _metric(
            'standardRequiredIncome',
            optional(value.requiredMonthlyIncome),
          ),
          PouchSectionHeading(
            title: strings.text('forecastEconomicAssumptions'),
          ),
          if (value.monthlyNetIncome != null)
            _metric(
              value.country == 'IR' && !value.customized
                  ? 'standardHouseholdIncome'
                  : 'standardNetIncome',
              money(value.monthlyNetIncome!),
            ),
          if (value.monthlyEssential != null)
            _metric('standardEssential', money(value.monthlyEssential!)),
          if (value.dailySpending != null && value.dailySpending! > 0)
            _metric('forecastLiving', money(value.dailySpending!)),
          if (value.monthlySaving != null)
            _metric('standardCapacity', money(value.monthlySaving!)),
          Text(strings.text('standardDeadlineMethod')),
          if (value.country == 'CA') ...[
            Text(strings.text('standardCanadaMethod')),
            SelectableText(strings.text('standardCanadaSources')),
          ] else if (value.country == 'IR') ...[
            Text(strings.text('standardIranLimitations')),
            SelectableText(strings.text('standardIranSource')),
          ] else ...[
            Text(strings.text('standardInternationalMethod')),
            const SelectableText(
              'https://data-explorer.oecd.org/\nhttps://data.worldbank.org/indicator/NE.CON.PRVT.CN\nhttps://data.worldbank.org/indicator/SP.POP.TOTL',
            ),
          ],
          for (final entry in value.observations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${strings.text('standardIndicator_${entry.indicator}')}: '
                '${localizeDigits(entry.value.toStringAsFixed(2), strings.language)} '
                '${entry.unit} · ${localizeDigits(entry.period, strings.language)}',
              ),
            ),
          if (value.exchangeRateTrillionths != null)
            Text(
              strings.text('standardCustomExchangeSource', {
                'to': value.currency,
                'from': widget.snapshot.preferences.currency,
                'rate': localizeDigits(
                  _rateText(value.exchangeRateTrillionths!),
                  strings.language,
                ),
              }),
            ),
          if (value.exchange != null)
            Text(
              strings.text('standardRateDate', {
                'date': value.exchange!['date'] as String,
              }),
            ),
          if (!value.customized)
            const SelectableText(
              'https://www.bankofcanada.ca/valet/docs\nhttps://www.tgju.org/profile/price_dollar_rl',
            ),
          if (value.downloaded != null)
            Text(
              strings.text('standardCachedDate', {'date': value.downloaded!}),
            ),
        ],
      ),
    );
    return widgets;
  }

  Widget _metric(String label, String value) =>
      ForecastMetric(label: widget.strings.text(label), value: value);

  String _rateText(int rate) {
    final whole = rate ~/ 1000000000000;
    final fraction = (rate % 1000000000000).toString().padLeft(12, '0');
    return '$whole.$fraction';
  }

  Future<void> _customize() async {
    final country = _country;
    final value = _forecast;
    final entry = _countries.firstWhere((item) => item.code == country);
    String initialAmount(int? amount) {
      if (amount == null) return '';
      return amountInput(amount, language: widget.strings.language);
    }

    final income = TextEditingController(
      text: initialAmount(value?.monthlyNetIncome),
    );
    final essential = TextEditingController(
      text: initialAmount(value?.monthlyEssential),
    );
    final daily = TextEditingController(
      text: initialAmount(value?.dailySpending),
    );
    final exchange = TextEditingController();
    final rate = value?.exchangeRateTrillionths;
    if (rate != null &&
        entry.currency != widget.snapshot.preferences.currency) {
      exchange.text = _rateText(rate);
    }
    var saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            Widget input(TextEditingController controller, String label) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      PouchMoneyInputFormatter(widget.strings.language),
                    ],
                    decoration: InputDecoration(
                      labelText:
                          '${widget.strings.text(label)} (${entry.currency})',
                    ),
                  ),
                );
            return AlertDialog(
              title: Text(widget.strings.text('standardCustomize')),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.strings.text('standardCustomizeHint')),
                      input(income, 'standardNetIncome'),
                      input(essential, 'standardEssential'),
                      input(daily, 'forecastLiving'),
                      if (entry.currency !=
                          widget.snapshot.preferences.currency)
                        TextField(
                          controller: exchange,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: widget.strings.text(
                              'standardCustomRate',
                              {
                                'to': entry.currency,
                                'from': widget.snapshot.preferences.currency,
                              },
                            ),
                            helperText: widget.strings.text(
                              'standardCustomRateHint',
                            ),
                            helperMaxLines: 4,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: Text(widget.strings.text('close')),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          update(() {
                            saving = true;
                          });
                          final saved = await widget.run(
                            () => widget.bridge.customizeEconomicProfile(
                              country: country,
                              monthlyNetIncome: income.text,
                              monthlyEssential: essential.text,
                              dailySpending: daily.text,
                              exchangeRate: exchange.text.trim().isEmpty
                                  ? null
                                  : exchange.text.trim(),
                            ),
                          );
                          if (context.mounted) {
                            if (saved) {
                              Navigator.pop(context);
                            } else {
                              update(() {
                                saving = false;
                              });
                            }
                          }
                        },
                  child: Text(widget.strings.text('save')),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      income.dispose();
      essential.dispose();
      daily.dispose();
      exchange.dispose();
    }
    if (mounted) await _load();
  }
}
