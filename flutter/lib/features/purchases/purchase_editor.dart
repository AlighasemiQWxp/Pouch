import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_formatters.dart';
import '../../widgets/pouch_date_picker.dart';

class PurchaseEditor extends StatefulWidget {
  const PurchaseEditor({
    required this.strings,
    required this.bridge,
    required this.currency,
    required this.calendar,
    required this.weekStart,
    required this.initialDate,
    required this.today,
    required this.onSave,
    this.editing = false,
    this.initialDescription = '',
    this.initialAmount = '',
    this.initialCategory = 'other',
    super.key,
  });
  final AppStrings strings;
  final PouchBridge bridge;
  final String currency, calendar, initialDate, today;
  final int weekStart;
  final bool editing;
  final String initialDescription, initialAmount, initialCategory;
  final Future<bool> Function(PurchaseValues values) onSave;

  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  late final _description = TextEditingController(
    text: widget.initialDescription,
  );
  late final _amount = TextEditingController(text: widget.initialAmount);
  late String _category = widget.initialCategory;
  late String _date = widget.initialDate;
  bool _saving = false;
  String? _error;
  bool _invalidAmount = false;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseMoneyEntry(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _invalidAmount = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _invalidAmount = false;
    });
    final description = _description.text.trim();
    var saved = false;
    try {
      saved = await widget.onSave(
        PurchaseValues(
          description.isEmpty ? widget.strings.text(_category) : description,
          _amount.text.trim(),
          _category,
          _date,
        ),
      );
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) _error = 'entrySaveFailed';
    });
    if (saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.strings.text(widget.editing ? 'editPurchase' : 'addPurchase'),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('expense-amount'),
                autofocus: true,
                enabled: !_saving,
                controller: _amount,
                inputFormatters: [
                  PouchMoneyInputFormatter(widget.strings.language),
                ],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.strings.text('amount'),
                  suffixText: widget.currency == 'TOMAN'
                      ? widget.strings.text('toman')
                      : widget.currency,
                  errorText: _invalidAmount
                      ? widget.strings.text('positiveAmount')
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const ValueKey('expense-date'),
                contentPadding: EdgeInsets.zero,
                title: Text(widget.strings.text('date')),
                subtitle: PouchDateLabel(
                  bridge: widget.bridge,
                  strings: widget.strings,
                  date: _date,
                  calendar: widget.calendar,
                ),
                trailing: widget.editing
                    ? null
                    : const Icon(Icons.calendar_month_outlined),
                onTap: widget.editing || _saving
                    ? null
                    : () async {
                        final date = await showPouchDatePicker(
                          context: context,
                          bridge: widget.bridge,
                          strings: widget.strings,
                          initialDate: _date,
                          calendar: widget.calendar,
                          weekStart: widget.weekStart,
                          firstDate: firstPouchRecordDate,
                          lastDate: widget.today,
                        );
                        if (mounted && date != null) {
                          setState(() => _date = date);
                        }
                      },
              ),
              Text(widget.strings.text('category')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final category in [
                    'food',
                    'transport',
                    'shopping',
                    'health',
                    'entertainment',
                    'bills',
                    'other',
                  ])
                    ChoiceChip(
                      label: Text(widget.strings.text(category)),
                      selected: category == _category,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('expense-note'),
                enabled: !_saving,
                controller: _description,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: widget.strings.text('optionalNote'),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null)
                Text(
                  widget.strings.text(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(widget.strings.text('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(widget.strings.text(_saving ? 'savingEntry' : 'save')),
        ),
      ],
    ),
  );
}

class PurchaseValues {
  const PurchaseValues(this.description, this.amount, this.category, this.date);
  final String description, amount, category, date;
}
