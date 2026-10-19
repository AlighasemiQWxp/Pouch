import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_formatters.dart';

class PurchaseEditor extends StatefulWidget {
  const PurchaseEditor({
    required this.strings,
    this.initialDescription = '',
    this.initialAmount = '',
    this.initialCategory = 'other',
    this.dateLabel,
    super.key,
  });

  final AppStrings strings;
  final String initialDescription;
  final String initialAmount;
  final String initialCategory;
  final Widget? dateLabel;

  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  late final _description = TextEditingController(
    text: widget.initialDescription,
  );
  late final _amount = TextEditingController(text: widget.initialAmount);
  late String _category = widget.initialCategory;
  bool _missingFields = false;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.strings.text(
        widget.initialDescription.isEmpty ? 'addPurchase' : 'editPurchase',
      ),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.dateLabel != null) ...[
            widget.dateLabel!,
            const SizedBox(height: 16),
          ],
          TextField(
            autofocus: true,
            textInputAction: TextInputAction.next,
            controller: _description,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: widget.strings.text('description'),
              errorText: _missingFields && _description.text.trim().isEmpty
                  ? widget.strings.text('requiredField')
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            inputFormatters: [
              PouchMoneyInputFormatter(widget.strings.language),
            ],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.strings.text('amount'),
              errorText: _missingFields && _amount.text.trim().isEmpty
                  ? widget.strings.text('requiredField')
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (_description.text.trim().isEmpty || _amount.text.trim().isEmpty) {
            setState(() => _missingFields = true);
            return;
          }
          Navigator.pop(
            context,
            PurchaseValues(_description.text.trim(), _amount.text, _category),
          );
        },
        child: Text(widget.strings.text('save')),
      ),
    ],
  );
}

class PurchaseValues {
  const PurchaseValues(this.description, this.amount, this.category);

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
