import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_formatters.dart';
import '../../widgets/pouch_widgets.dart';
import '../planned/planned_item_widgets.dart';

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

  Future<void> _edit(BuildContext context, PouchRequiredExpense expense) =>
      editPlannedItem(
        context: context,
        bridge: bridge,
        snapshot: snapshot,
        strings: strings,
        today: today,
        run: run,
        recurringExpense: expense,
      );
}
