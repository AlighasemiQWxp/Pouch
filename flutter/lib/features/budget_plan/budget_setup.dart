import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../widgets/pouch_date_picker.dart';
import '../planned/planned_item_widgets.dart';

Future<bool> showBudgetSetup({
  required BuildContext context,
  required PouchBridge bridge,
  required PouchSnapshot snapshot,
  required AppStrings strings,
  required String today,
  required PouchMutation run,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BudgetSetup(
        bridge: bridge,
        snapshot: snapshot,
        strings: strings,
        today: today,
        run: run,
      ),
    ) ??
    false;

class BudgetSetup extends StatefulWidget {
  const BudgetSetup({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    super.key,
  });
  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  @override
  State<BudgetSetup> createState() => _BudgetSetupState();
}

class _BudgetSetupState extends State<BudgetSetup> {
  late PouchSnapshot _snapshot = widget.snapshot;
  late String _currency = _snapshot.preferences.currency;
  late String _calendar = _snapshot.preferences.calendar;
  late String _through = DateTime.parse('${widget.today}T00:00:00Z')
      .add(const Duration(days: 29))
      .toIso8601String()
      .substring(0, 10);
  final _amount = TextEditingController();
  final _savings = TextEditingController();
  final _incomeId = 'setup-${DateTime.now().microsecondsSinceEpoch}';
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _periodId;

  @override
  void dispose() {
    _amount.dispose();
    _savings.dispose();
    super.dispose();
  }

  Future<bool> _save(Future<PouchSnapshot> Function() operation) async {
    final saved = await widget.run(() async {
      final snapshot = await operation();
      _snapshot = snapshot;
      return snapshot;
    });
    if (mounted) setState(() {});
    return saved;
  }

  Future<void> _next() async {
    if (_busy) return;
    if (_step == 1 && (parseMoneyEntry(_amount.text) ?? 0) <= 0) {
      setState(() => _error = 'positiveAmount');
      return;
    }
    final savings = _savings.text.trim().isEmpty
        ? 0
        : parseMoneyEntry(_savings.text);
    if (_step == 2 && savings == null) {
      setState(() => _error = 'invalidAmount');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var saved = false;
    try {
      if (_step == 0) {
        final preferences = _snapshot.preferences;
        saved = await _save(
          () => widget.bridge.updatePreferences(
            country: preferences.country,
            currency: _currency,
            language: preferences.language,
            calendar: _calendar,
            weekStart: preferences.weekStart,
          ),
        );
      } else if (_step == 1) {
        saved = await _save(
          () => widget.bridge.receiveIncome(
            id: _incomeId,
            date: widget.today,
            amount: _amount.text.trim(),
            startNew: true,
            kind: 'once',
            through: _through,
          ),
        );
        if (saved) {
          _periodId = _snapshot.periods
              .where((p) => p.start == widget.today)
              .first
              .id;
        }
      } else {
        saved = true;
        if (savings! > 0) {
          saved = await _save(
            () => widget.bridge.saveBudgetPlan(
              periodId: _periodId!,
              effective: widget.today,
              savings: _savings.text.trim(),
            ),
          );
        }
      }
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!saved) _error = 'entrySaveFailed';
    });
    if (!saved) return;
    if (_step == 2) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.strings;
    final hasRecords =
        _snapshot.days.any((day) => day.purchases.isNotEmpty) ||
        _snapshot.income.isNotEmpty ||
        _snapshot.expectedIncome.isNotEmpty ||
        _snapshot.planned.isNotEmpty ||
        _snapshot.essentials.isNotEmpty;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          t.text(['setupRegion', 'setupMoney', 'setupOptional'][_step]),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.text('setupStep', {
                    'step': localizeDigits('${_step + 1}', t.language),
                  }),
                ),
                const SizedBox(height: 16),
                if (_step == 0) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: t.text('currency')),
                    items: [
                      for (final value in [
                        'TOMAN',
                        'CAD',
                        'USD',
                        'EUR',
                        'GBP',
                        'AUD',
                        'NZD',
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            value == 'TOMAN' ? t.text('toman') : value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy || hasRecords
                        ? null
                        : (value) => setState(() => _currency = value!),
                  ),
                  if (hasRecords) Text(t.text('currencyLocked')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _calendar,
                    decoration: InputDecoration(
                      labelText: t.text('calendarPreference'),
                    ),
                    items: [
                      for (final value in ['gregory', 'persian'])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            t.text(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _calendar = value!),
                  ),
                ],
                if (_step == 1) ...[
                  Text(t.text('setupMoneyHint')),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('setup-amount'),
                    controller: _amount,
                    autofocus: true,
                    enabled: !_busy,
                    inputFormatters: [PouchMoneyInputFormatter(t.language)],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t.text('amount'),
                      suffixText: _currency == 'TOMAN'
                          ? t.text('toman')
                          : _currency,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(t.text('setupUntil')),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final date = await showPouchDatePicker(
                              context: context,
                              bridge: widget.bridge,
                              strings: t,
                              initialDate: _through,
                              calendar: _calendar,
                              weekStart: _snapshot.preferences.weekStart,
                              firstDate: widget.today,
                              lastDate: lastPouchRecordDate,
                            );
                            if (mounted && date != null) {
                              setState(() => _through = date);
                            }
                          },
                    child: PouchDateLabel(
                      bridge: widget.bridge,
                      strings: t,
                      date: _through,
                      calendar: _calendar,
                    ),
                  ),
                ],
                if (_step == 2) ...[
                  Text(t.text('setupOptionalHint')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            await editPlannedItem(
                              context: context,
                              bridge: widget.bridge,
                              snapshot: _snapshot,
                              strings: t,
                              today: widget.today,
                              run: _save,
                              initialPeriodId: _periodId,
                            );
                            if (mounted) setState(() {});
                          },
                    icon: const Icon(Icons.add),
                    label: Text(t.text('addPlannedExpense')),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('setup-savings'),
                    controller: _savings,
                    enabled: !_busy,
                    inputFormatters: [PouchMoneyInputFormatter(t.language)],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t.text('setupSavings'),
                      suffixText: _currency == 'TOMAN'
                          ? t.text('toman')
                          : _currency,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(t.text('savingsSetAsideHint')),
                  const SizedBox(height: 12),
                  Text(t.text('estimateRecordedOnly')),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      t.text(_error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, _step == 2),
            child: Text(t.text(_step == 2 ? 'setupSkip' : 'cancel')),
          ),
          if (_step == 1)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _step = 0;
                      _error = null;
                    }),
              child: Text(t.text('previous')),
            ),
          FilledButton(
            key: const ValueKey('setup-next'),
            onPressed: _busy ? null : _next,
            child: Text(
              t.text(
                _busy ? 'savingEntry' : (_step == 2 ? 'setupFinish' : 'next'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
