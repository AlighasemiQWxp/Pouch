import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_models.dart';
import '../../core/pouch_formatters.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_motion.dart';
import '../../widgets/pouch_date_picker.dart';
import 'purchase_editor.dart';
import '../planned/planned_item_widgets.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({
    required this.bridge,
    required this.snapshot,
    required this.strings,
    required this.today,
    required this.run,
    required this.undo,
    this.selectedDate,
    this.embedded = false,
    this.working = false,
    super.key,
  });
  final PouchBridge bridge;
  final PouchSnapshot snapshot;
  final AppStrings strings;
  final String today;
  final PouchMutation run;
  final PouchUndo undo;
  final String? selectedDate;
  final bool embedded, working;
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late String date = widget.selectedDate ?? widget.today;
  late bool allDates = !widget.embedded;

  @override
  void didUpdateWidget(covariant PurchasesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate) {
      date = widget.selectedDate ?? widget.today;
    }
  }

  String query = '';
  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final day in widget.snapshot.days)
        if (allDates || day.date == date)
          for (final purchase in day.purchases)
            if (purchase.description.toLowerCase().contains(
              query.toLowerCase(),
            ))
              (day.date, purchase),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final upcoming =
        widget.snapshot.planned
            .where(
              (item) =>
                  item.kind == 'expense' &&
                  item.status == 'pending' &&
                  (allDates || item.date == date) &&
                  item.description.toLowerCase().contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final futureDay = date.compareTo(widget.today) > 0;
    final children = <Widget>[
      if (!widget.embedded)
        PouchIntro(
          eyebrow: widget.strings.text('spendingLabel'),
          title: widget.strings.text('navPurchases'),
          description: widget.strings.text('purchasesPageHint'),
        ),
      PouchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.strings.text(
                    widget.embedded ? 'dayPurchases' : 'purchaseHistory',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                PouchPrimaryButton(
                  label: widget.strings.text(
                    futureDay ? 'addPlannedExpense' : 'addPurchase',
                  ),
                  icon: Icons.add,
                  onPressed: widget.working ? null : () => edit(date, null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.embedded)
              PouchDateLabel(
                bridge: widget.bridge,
                strings: widget.strings,
                date: date,
                calendar: widget.snapshot.preferences.calendar,
              ),
            if (!widget.embedded)
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  labelText: widget.strings.text('searchPurchases'),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            if (!widget.embedded)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.strings.text('allDates')),
                value: allDates,
                onChanged: (value) => setState(() => allDates = value),
              ),
            if (!allDates && !widget.embedded)
              OutlinedButton.icon(
                onPressed: pickDate,
                icon: const Icon(Icons.calendar_month),
                label: PouchDateLabel(
                  bridge: widget.bridge,
                  strings: widget.strings,
                  date: date,
                  calendar: widget.snapshot.preferences.calendar,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (entries.isEmpty && upcoming.isEmpty)
        PouchEmptyState(
          title: widget.strings.text('noPurchases'),
          message: widget.strings.text(
            futureDay ? 'futureExpenseHint' : 'purchaseEmptyHint',
          ),
          icon: Icons.receipt_long_outlined,
        ),
      if (upcoming.isNotEmpty) ...[
        PouchSectionHeading(title: widget.strings.text('pendingExpenses')),
        for (final item in upcoming)
          PlannedItemTile(
            key: ValueKey('daily-plan-${item.id}'),
            item: item,
            strings: widget.strings,
            currency: widget.snapshot.preferences.currency,
            calendar: widget.snapshot.preferences.calendar,
            weekStart: widget.snapshot.preferences.weekStart,
            startDate: widget.snapshot.startDate,
            bridge: widget.bridge,
            today: widget.today,
            run: widget.run,
            working: widget.working,
            onEdit: () => editPlannedItem(
              context: context,
              bridge: widget.bridge,
              snapshot: widget.snapshot,
              strings: widget.strings,
              today: widget.today,
              run: widget.run,
              existing: item,
            ),
            onDelete: () => deletePlannedItem(
              context: context,
              bridge: widget.bridge,
              strings: widget.strings,
              run: widget.run,
              undo: widget.undo,
              item: item,
            ),
          ),
        const SizedBox(height: 16),
      ],
      if (entries.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PouchSectionHeading(
            title: widget.strings.text('paidExpenses'),
          ),
        ),
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PouchCard(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(entry.$2.description),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PouchDateLabel(
                    bridge: widget.bridge,
                    strings: widget.strings,
                    date: entry.$1,
                    calendar: widget.snapshot.preferences.calendar,
                  ),
                  Text(
                    '${widget.strings.text(entry.$2.category)} · ${formatMoney(entry.$2.amount, widget.snapshot.preferences.currency, widget.strings)}',
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                enabled: !widget.working,
                onSelected: (action) {
                  if (action == 'edit') {
                    edit(entry.$1, entry.$2);
                  } else {
                    remove(entry.$1, entry.$2);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(widget.strings.text('edit')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(widget.strings.text('delete')),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return PouchPage(children: children);
  }

  Future<void> pickDate() async {
    final picked = await showPouchDatePicker(
      context: context,
      bridge: widget.bridge,
      strings: widget.strings,
      initialDate: date,
      calendar: widget.snapshot.preferences.calendar,
      weekStart: widget.snapshot.preferences.weekStart,
      firstDate: firstPouchRecordDate,
      lastDate: lastPouchRecordDate,
    );
    if (mounted && picked != null) setState(() => date = picked);
  }

  Future<void> edit(String day, PouchPurchase? purchase) async {
    if (widget.working) return;
    if (purchase == null && day.compareTo(widget.today) > 0) {
      await editPlannedItem(
        context: context,
        bridge: widget.bridge,
        snapshot: widget.snapshot,
        strings: widget.strings,
        today: widget.today,
        run: widget.run,
        initialDate: day,
      );
      return;
    }
    final value = await showDialog<PurchaseValues>(
      context: context,
      builder: (_) => PurchaseEditor(
        strings: widget.strings,
        dateLabel: PouchDateLabel(
          bridge: widget.bridge,
          strings: widget.strings,
          date: day,
          calendar: widget.snapshot.preferences.calendar,
        ),
        initialDescription: purchase?.description ?? '',
        initialAmount: purchase == null
            ? ''
            : amountInput(purchase.amount, language: widget.strings.language),
        initialCategory: purchase?.category ?? 'other',
      ),
    );
    if (value == null || !mounted) return;
    if (purchase == null) {
      final saved = await widget.run(
        () => widget.bridge.addPurchase(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          date: day,
          description: value.description,
          amount: value.amount,
          category: value.category,
        ),
      );
      if (saved && mounted) PouchMotion.celebrate(context);
    } else {
      await widget.run(
        () => widget.bridge.editPurchase(
          date: day,
          id: purchase.id,
          description: value.description,
          amount: value.amount,
          category: value.category,
        ),
      );
    }
  }

  Future<void> remove(String day, PouchPurchase purchase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('deletePurchase')),
        content: Text(purchase.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final saved = await widget.run(
      () => widget.bridge.removePurchase(day, purchase.id),
    );
    if (saved && mounted) {
      showPouchUndoMessage(context, widget.strings, 'deleted', widget.undo);
    }
  }
}
