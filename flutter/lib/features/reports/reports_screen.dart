import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';

enum _ReportMode { range, specific, weekly, monthly }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportMode _mode = _ReportMode.range;
  late String _from = _subtractDays(widget.today, 6, widget.snapshot.startDate);
  late String _through = widget.today;
  late String _anchor = widget.today;
  final List<String> _selectedDays = [];
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _previewKey = GlobalKey();
  PouchReport? _report;
  bool _previewFailed = false;
  bool _reportLoading = false;
  bool _printing = false;
  int _requestVersion = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return PouchPage(
      controller: _scrollController,
      children: [
        PouchIntro(
          eyebrow: strings.text('insightsLabel'),
          title: strings.text('reports'),
          description: strings.text('reportsPageHint'),
        ),
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSectionHeading(title: strings.text('reportBuilder')),
              const SizedBox(height: 14),
              DropdownButtonFormField<_ReportMode>(
                initialValue: _mode,
                decoration: InputDecoration(
                  labelText: strings.text('reportMode'),
                ),
                items: _ReportMode.values
                    .map(
                      (value) => DropdownMenuItem<_ReportMode>(
                        value: value,
                        child: Text(strings.text(_modeKey(value))),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() {
                  _mode = value ?? _ReportMode.range;
                  _report = null;
                  _previewFailed = false;
                  _reportLoading = false;
                  _requestVersion++;
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == _ReportMode.range) _buildRangeInputs(),
              if (_mode == _ReportMode.specific) _buildSpecificInputs(),
              if (_mode == _ReportMode.weekly || _mode == _ReportMode.monthly)
                _buildAnchorInput(),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PouchPrimaryButton(
                  label: strings.text('preview'),
                  icon: _reportLoading
                      ? Icons.hourglass_top_rounded
                      : Icons.visibility_outlined,
                  onPressed: _reportLoading ? null : _loadReport,
                ),
              ),
            ],
          ),
        ),
        if (_reportLoading || _report != null || _previewFailed) ...[
          const SizedBox(height: 14),
          KeyedSubtree(
            key: _previewKey,
            child: _reportLoading
                ? const PouchCard(child: LinearProgressIndicator())
                : _previewFailed
                ? PouchCard(
                    child: PouchInlineError(strings.text('invalidReport')),
                  )
                : _buildPreview(_report!),
          ),
        ],
      ],
    );
  }

  Widget _buildRangeInputs() => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _dateButton(
        'from',
        _from,
        () => _pickDate((value) => _from = value, _from),
      ),
      _dateButton(
        'to',
        _through,
        () => _pickDate((value) => _through = value, _through),
      ),
    ],
  );

  Widget _buildSpecificInputs() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: () async {
            await _pickDate((value) {
              if (!_selectedDays.contains(value)) _selectedDays.add(value);
            }, widget.today);
            if (!mounted) return;
            setState(() {
              _report = null;
              _previewFailed = false;
              _reportLoading = false;
              _requestVersion++;
            });
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(widget.strings.text('addDay')),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        widget.strings.text('selectedDays'),
        style: TextStyle(color: context.pouchPalette.muted, fontSize: 12),
      ),
      const SizedBox(height: 6),
      if (_selectedDays.isEmpty)
        Text(
          widget.strings.text('noSelectedDays'),
          style: TextStyle(color: context.pouchPalette.muted),
        )
      else
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final value in [..._selectedDays]..sort())
              InputChip(
                label: PouchDateLabel(
                  bridge: widget.bridge,
                  strings: widget.strings,
                  date: value,
                  calendar: widget.snapshot.preferences.calendar,
                ),
                onDeleted: () => setState(() {
                  _selectedDays.remove(value);
                  _report = null;
                  _previewFailed = false;
                  _reportLoading = false;
                  _requestVersion++;
                }),
              ),
          ],
        ),
    ],
  );

  Widget _buildAnchorInput() => _dateButton(
    'date',
    _anchor,
    () => _pickDate((value) => _anchor = value, _anchor),
  );

  Widget _dateButton(String label, String value, VoidCallback onPressed) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.calendar_month_rounded),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.strings.text(label)}: '),
            PouchDateLabel(
              bridge: widget.bridge,
              strings: widget.strings,
              date: value,
              calendar: widget.snapshot.preferences.calendar,
            ),
          ],
        ),
      );

  Widget _buildPreview(PouchReport report) {
    final strings = widget.strings;
    final currency = widget.snapshot.preferences.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PouchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.text('reportTitle'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.text('exportPdf'),
                    onPressed: _printing ? null : () => _print(report),
                    icon: _printing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.picture_as_pdf_outlined,
                            color: context.pouchPalette.goldDeep,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${strings.text('dayCount')}: ${localizeDigits('${report.dates.length}', strings.language)}',
                style: TextStyle(color: context.pouchPalette.muted),
              ),
              const SizedBox(height: 3),
              Text(
                '${strings.text('totalSpent')}: ${formatMoney(report.total, currency, strings)}',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${strings.text('totalPlanned')}: ${formatMoney(report.reserved, currency, strings)}',
                style: TextStyle(color: context.pouchPalette.muted),
              ),
              const SizedBox(height: 13),
              PouchSectionHeading(title: strings.text('categoryTotals')),
              for (final total in report.categories)
                _amountRow(
                  strings.text(total.category),
                  total.amount,
                  currency,
                  strings,
                ),
              const SizedBox(height: 9),
              PouchSectionHeading(title: strings.text('dailyTotals')),
              for (final total in report.daily)
                _amountRow(
                  '',
                  total.amount,
                  currency,
                  strings,
                  date: total.date,
                ),
              const SizedBox(height: 9),
              PouchSectionHeading(title: strings.text('details')),
              if (report.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    strings.text('reportEmpty'),
                    style: TextStyle(color: context.pouchPalette.muted),
                  ),
                )
              else
                for (final entry in report.entries)
                  _amountRow(
                    entry.description,
                    entry.amount,
                    currency,
                    strings,
                    date: entry.date,
                    subtitle: strings.text(entry.category),
                  ),
              if (report.planned.isNotEmpty) ...[
                const SizedBox(height: 12),
                PouchSectionHeading(title: strings.text('plannedReport')),
                for (final item in report.planned)
                  _amountRow(
                    item.description,
                    item.amount,
                    currency,
                    strings,
                    date: item.date,
                    subtitle: strings.text(item.category),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                strings.text('reportFootnote'),
                style: TextStyle(
                  color: context.pouchPalette.muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _amountRow(
    String label,
    int amount,
    String currency,
    AppStrings strings, {
    String? date,
    String? subtitle,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (date != null) ...[
                    PouchDateLabel(
                      bridge: widget.bridge,
                      strings: strings,
                      date: date,
                      calendar: widget.snapshot.preferences.calendar,
                    ),
                    if (label.isNotEmpty) const Text(' · '),
                  ],
                  if (label.isNotEmpty)
                    Flexible(
                      child: Text(label, style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.pouchPalette.muted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatMoney(amount, currency, strings),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Future<void> _loadReport() async {
    if ((_mode == _ReportMode.range && _from.compareTo(_through) > 0) ||
        (_mode == _ReportMode.specific && _selectedDays.isEmpty)) {
      setState(() {
        _report = null;
        _previewFailed = true;
        _reportLoading = false;
        _requestVersion++;
      });
      _revealPreview();
      return;
    }
    final requestVersion = ++_requestVersion;
    setState(() {
      _report = null;
      _previewFailed = false;
      _reportLoading = true;
    });
    _revealPreview();
    try {
      final report = await _createReport();
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _report = report;
        _reportLoading = false;
      });
    } catch (_) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _previewFailed = true;
        _reportLoading = false;
      });
    }
    _revealPreview();
  }

  void _revealPreview() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _previewKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 280),
        alignment: 0.05,
      );
    });
  }

  Future<PouchReport> _createReport() {
    switch (_mode) {
      case _ReportMode.range:
        return widget.bridge.reportRange(_from, _through);
      case _ReportMode.specific:
        return widget.bridge.reportSpecific([..._selectedDays]);
      case _ReportMode.weekly:
        return widget.bridge.reportWeek(
          _anchor,
          widget.snapshot.preferences.weekStart,
        );
      case _ReportMode.monthly:
        return widget.bridge.reportMonth(
          _anchor,
          widget.snapshot.preferences.calendar,
        );
    }
  }

  Future<void> _pickDate(
    void Function(String value) apply,
    String initial,
  ) async {
    final picked = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: initial,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: widget.snapshot.startDate,
      lastDate: widget.today,
    );
    if (picked != null && mounted) {
      setState(() {
        apply(picked);
        _report = null;
        _previewFailed = false;
        _reportLoading = false;
        _requestVersion++;
      });
    }
  }

  Future<void> _print(PouchReport report) async {
    setState(() => _printing = true);
    try {
      await widget.bridge.printReport(
        widget.strings.text('reportTitle'),
        await _reportHtml(report),
      );
      if (mounted) showPouchMessage(context, widget.strings, 'printHint');
    } catch (_) {
      if (mounted) showPouchMessage(context, widget.strings, 'printFailed');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<String> _reportHtml(PouchReport report) async {
    final strings = widget.strings;
    final currency = widget.snapshot.preferences.currency;
    final dailyRows = <String>[];
    for (final total in report.daily) {
      final date = await formatPouchDate(
        widget.bridge,
        total.date,
        widget.snapshot.preferences.calendar,
        strings,
      );
      dailyRows.add(
        '<tr><td>${_escape(date)}</td><td>${_escape(formatMoney(total.amount, currency, strings))}</td></tr>',
      );
    }
    final rows = <String>[];
    for (final entry in report.entries) {
      final date = await formatPouchDate(
        widget.bridge,
        entry.date,
        widget.snapshot.preferences.calendar,
        strings,
      );
      rows.add(
        '<tr><td>${_escape(date)}</td><td>${_escape(entry.description)}</td><td>${_escape(strings.text(entry.category))}</td><td>${_escape(formatMoney(entry.amount, currency, strings))}</td></tr>',
      );
    }
    final pendingRows = <String>[];
    for (final entry in report.planned) {
      final date = await formatPouchDate(
        widget.bridge,
        entry.date,
        widget.snapshot.preferences.calendar,
        strings,
      );
      pendingRows.add(
        '<tr><td>${_escape(date)}</td><td>${_escape(entry.description)}</td><td>${_escape(strings.text(entry.category))}</td><td>${_escape(formatMoney(entry.amount, currency, strings))}</td></tr>',
      );
    }
    return '<!doctype html><html lang="${strings.language}"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${_escape(strings.text('reportTitle'))}</title><style>body{font-family:Arial,sans-serif;color:#30291f;padding:24px}h1{font-size:22px}table{border-collapse:collapse;width:100%;margin:14px 0 24px}th,td{border-bottom:1px solid #e8dcc4;padding:9px;text-align:start}th{background:#f7edd9}.summary{padding:14px;background:#f7f3ea;border-radius:12px}</style><body dir="${strings.isPersian ? 'rtl' : 'ltr'}"><h1>${_escape(strings.text('reportTitle'))}</h1><div class="summary">${_escape(strings.text('totalSpent'))}: ${_escape(formatMoney(report.total, currency, strings))}<br>${_escape(strings.text('totalPlanned'))}: ${_escape(formatMoney(report.reserved, currency, strings))}</div><h2>${_escape(strings.text('dailyTotals'))}</h2><table><tbody>${dailyRows.join()}</tbody></table><h2>${_escape(strings.text('details'))}</h2><table><thead><tr><th>${_escape(strings.text('date'))}</th><th>${_escape(strings.text('description'))}</th><th>${_escape(strings.text('category'))}</th><th>${_escape(strings.text('amount'))}</th></tr></thead><tbody>${rows.join()}</tbody></table><h2>${_escape(strings.text('plannedReport'))}</h2><table><tbody>${pendingRows.join()}</tbody></table><p>${_escape(strings.text('reportFootnote'))}</p></body></html>';
  }

  String _modeKey(_ReportMode value) => switch (value) {
    _ReportMode.range => 'range',
    _ReportMode.specific => 'specific',
    _ReportMode.weekly => 'weekly',
    _ReportMode.monthly => 'monthly',
  };
}

String _escape(String value) => const HtmlEscape().convert(value);
String _subtractDays(String value, int days, String minimum) {
  final date = DateTime.parse('${value}T00:00:00Z')
      .subtract(Duration(days: days));
  final start = DateTime.parse('${minimum}T00:00:00Z');
  return _iso(date.isBefore(start) ? start : date);
}

String _iso(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
