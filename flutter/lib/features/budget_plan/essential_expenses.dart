import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_formatters.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_date_picker.dart';

class EssentialExpenses extends StatelessWidget {
  const EssentialExpenses({
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
  Widget build(BuildContext context) => PouchCard(
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(strings.text('commitments')),
      subtitle: Text(strings.text('recurringBillsHint')),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: Text(strings.text('addRecurringExpense')),
          ),
        ),
        const SizedBox(height: 8),
        Text(strings.text('essentialRecurrenceHint')),
        const SizedBox(height: 12),
        for (final expense in snapshot.essentials.where(
          (item) => item.until == null,
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(expense.name),
            subtitle: Text(
              '${formatMoney(expense.amount, snapshot.preferences.currency, strings)} · ${strings.text('schedule_${expense.recurrence}')}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: strings.text('edit'),
                  onPressed: () => _edit(context, expense),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: strings.text('stopRepeating'),
                  onPressed: () => _stop(context, expense),
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _stop(BuildContext context, PouchRequiredExpense expense) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('stopRepeating')),
        content: Text(strings.text('stopEssentialHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.text('stopRepeating')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await run(() => bridge.stopEssentialExpense(expense.id, today));
    }
  }

  Future<void> _edit(
    BuildContext context,
    PouchRequiredExpense? expense,
  ) async {
    final name = TextEditingController(text: expense?.name ?? '');
    final amount = TextEditingController(
      text: expense == null
          ? ''
          : amountInput(expense.amount, language: strings.language),
    );
    final days = TextEditingController(
      text: '${expense?.customDays == 0 ? 7 : expense?.customDays ?? 7}',
    );
    var date = expense?.date ?? today;
    var kind = expense?.recurrence ?? 'monthly';
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(strings.text(expense == null ? 'addExpense' : 'edit')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: strings.text('expenseName'),
                  ),
                ),
                TextField(
                  controller: amount,
                  inputFormatters: [PouchMoneyInputFormatter(strings.language)],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: strings.text('amount'),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  items: [
                    for (final value in [
                      'once',
                      'weekly',
                      'biweekly',
                      'monthly',
                      'custom',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(strings.text('schedule_$value')),
                      ),
                  ],
                  onChanged: (value) => setState(() => kind = value!),
                ),
                if (kind == 'custom')
                  TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.text('intervalDays'),
                    ),
                  ),
                TextButton(
                  onPressed: () async {
                    final picked = await showPouchDatePicker(
                      context: context,
                      bridge: bridge,
                      strings: strings,
                      initialDate: date,
                      calendar: snapshot.preferences.calendar,
                      weekStart: snapshot.preferences.weekStart,
                      firstDate: firstPouchRecordDate,
                      lastDate: '3797-12-31',
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                  child: PouchDateLabel(
                    bridge: bridge,
                    strings: strings,
                    date: date,
                    calendar: snapshot.preferences.calendar,
                  ),
                ),
                if (expense != null)
                  Text(strings.text('essentialCorrectionHint')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.text('saveChanges')),
            ),
          ],
        ),
      ),
    );
    final accepted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    final savedName = name.text.trim();
    final savedAmount = amount.text.trim();
    var digits = days.text;
    for (var digit = 0; digit < 10; digit++) {
      digits = digits
          .replaceAll('۰۱۲۳۴۵۶۷۸۹'[digit], '$digit')
          .replaceAll('٠١٢٣٤٥٦٧٨٩'[digit], '$digit');
    }
    final interval = int.tryParse(digits) ?? 0;
    await route.completed;
    name.dispose();
    amount.dispose();
    days.dispose();
    if (accepted == true) {
      await run(
        () => bridge.saveEssentialExpense(
          id:
              expense?.id ??
              'essential-${DateTime.now().microsecondsSinceEpoch}',
          name: savedName,
          amount: savedAmount,
          date: date,
          kind: kind,
          customDays: interval,
        ),
      );
    }
  }
}
