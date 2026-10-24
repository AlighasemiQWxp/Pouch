import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pouch/core/app_strings.dart';
import 'package:pouch/core/pouch_formatters.dart';
import 'package:pouch/core/pouch_models.dart';
import 'package:pouch/core/pouch_theme.dart';
import 'package:pouch/features/budget_plan/budget_setup.dart';
import 'package:pouch/features/planned/planned_item_widgets.dart';
import 'package:pouch/features/purchases/purchase_editor.dart';
import 'package:pouch/main.dart';
import 'package:pouch/features/reports/reports_screen.dart';

import 'application_flow_test.dart'
    show TestBridge, records, active, target, settleApp;

class SetupBridge extends TestBridge {
  bool failReceipt = false;
  int receiptCalls = 0;
  String? receiptThrough;
  String? billRepeat;
  int reportCalls = 0;
  @override
  Future<PouchReport> reportMonth(String anchor, String calendar) async {
    reportCalls++;
    return const PouchReport(
      dates: ['2024-01-10'],
      entries: [],
      daily: [],
      categories: [],
      planned: [],
      total: 0,
      reserved: 0,
    );
  }

  @override
  Future<PouchSnapshot> updatePreferences({
    required String country,
    required String currency,
    required String language,
    required String calendar,
    required int weekStart,
  }) async => records(empty: true, language: language);

  @override
  Future<PouchSnapshot> receiveIncome({
    required String id,
    required String date,
    required String amount,
    String? periodId,
    required bool startNew,
    String kind = 'monthly',
    int customDays = 7,
    String? through,
    bool expected = false,
  }) async {
    receiptCalls++;
    if (failReceipt) throw StateError('Could not save');
    expect(startNew, isTrue);
    expect(kind, 'once');
    receiptThrough = through;
    return super.receiveIncome(
      id: id,
      date: date,
      amount: '${parseMoneyEntry(amount)! / 100}',
      periodId: periodId,
      startNew: startNew,
      kind: kind,
      customDays: customDays,
      through: through,
    );
  }

  @override
  Future<PouchSnapshot> saveEssentialExpense({
    required String id,
    required String name,
    required String amount,
    required String date,
    required String kind,
    required int customDays,
  }) async {
    billRepeat = kind;
    return records();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final localizedStrings = <String, AppStrings>{};
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fa');
    for (final language in ['en', 'fa']) {
      localizedStrings[language] = await AppStrings.load(language);
    }
  });

  test('Money input validates localized amounts without rounding invalid precision', () {
    expect(parseMoneyEntry('۱٬۲۳۴٫۵۰'), 123450);
    expect(parseMoneyEntry('١٢.٥'), 1250);
    expect(parseMoneyEntry('1.234'), isNull);
    expect(parseMoneyEntry(''), isNull);
    expect(parseMoneyEntry('-10'), isNull);
    expect(parseMoneyEntry('0'), 0);
  });

  for (final language in ['en', 'fa']) {
    testWidgets(
      'Setup preserves failed input and saves one budget in $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final strings = localizedStrings[language]!;
        final bridge = SetupBridge()..failReceipt = true;
        bool? finished;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPouchTheme(),
            builder: (context, child) => Directionality(
              textDirection: language == 'fa'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Directionality(
                  textDirection: language == 'fa'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: FilledButton(
                    onPressed: () async {
                      finished = await showBudgetSetup(
                        context: context,
                        bridge: bridge,
                        snapshot: records(empty: true, language: language),
                        strings: strings,
                        today: active.start,
                        run: (operation) async {
                          try {
                            await operation();
                            return true;
                          } catch (_) {
                            return false;
                          }
                        },
                      );
                    },
                    child: const Text('Open setup'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open setup'));
        await settleApp(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('setup-next')));
        await settleApp(tester);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byKey(const ValueKey('setup-amount')), '0');
        await tester.tap(find.byKey(const ValueKey('setup-next')));
        await settleApp(tester);
        expect(bridge.receiptCalls, 0);
        expect(find.text(strings.text('positiveAmount')), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('setup-amount')),
          language == 'fa' ? '۵۰۰' : '500',
        );
        await tester.tap(find.byKey(const ValueKey('setup-next')));
        await settleApp(tester);
        expect(bridge.receivedIncome, isEmpty);
        expect(find.text(strings.text('entrySaveFailed')), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('setup-amount')))
              .controller!
              .text,
          isNotEmpty,
        );
        bridge.failReceipt = false;
        await tester.tap(find.byKey(const ValueKey('setup-next')));
        await settleApp(tester);
        expect(bridge.receivedIncome, hasLength(1));
        expect(bridge.receiptThrough, '2024-02-06');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(strings.text('setupSkip')));
        await settleApp(tester);
        expect(finished, isTrue);
        expect(bridge.receivedIncome, hasLength(1));
        expect(bridge.savingsPlans, isEmpty);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets('Expense retries keep the amount and optional note', (
    tester,
  ) async {
    final strings = localizedStrings['en']!;
    var accept = false;
    PurchaseValues? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => PurchaseEditor(
                  strings: strings,
                  bridge: TestBridge(),
                  currency: 'CAD',
                  calendar: 'gregory',
                  weekStart: 0,
                  initialDate: '2024-01-10',
                  today: '2024-01-10',
                  onSave: (value) async {
                    if (accept) saved = value;
                    return accept;
                  },
                ),
              ),
              child: const Text('Add'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await settleApp(tester);
    await tester.enterText(
      find.byKey(const ValueKey('expense-amount')),
      '12.50',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, strings.text('food')));
    await tester.tap(find.text(strings.text('save')));
    await settleApp(tester);
    expect(find.byType(PurchaseEditor), findsOneWidget);
    expect(find.text(strings.text('entrySaveFailed')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('expense-amount')))
          .controller!
          .text,
      '12.50',
    );
    accept = true;
    await tester.tap(find.text(strings.text('save')));
    await settleApp(tester);
    expect(find.byType(PurchaseEditor), findsNothing);
    expect(saved!.description, strings.text('food'));
    expect(saved!.category, 'food');
    expect(saved!.date, '2024-01-10');
  });

  testWidgets('A repeating bill uses the same entry form as a one-time bill', (
    tester,
  ) async {
    final strings = localizedStrings['en']!;
    final bridge = SetupBridge();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => editPlannedItem(
                context: context,
                bridge: bridge,
                snapshot: records(),
                strings: strings,
                today: active.start,
                run: (operation) async {
                  await operation();
                  return true;
                },
              ),
              child: const Text('Add bill'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add bill'));
    await settleApp(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Rent');
    await tester.enterText(find.byType(TextField).at(1), '100');
    final repeat = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == strings.text('billRepeat'),
    );
    await tester.ensureVisible(repeat);
    await tester.tap(repeat);
    await settleApp(tester);
    await tester.tap(find.text(strings.text('schedule_monthly')).last);
    await settleApp(tester);
    await tester.tap(find.text(strings.text('save')));
    await settleApp(tester);
    expect(bridge.billRepeat, 'monthly');
    expect(bridge.plans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Goal shortcut opens that goal inside Insights', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final strings = localizedStrings['en']!;
    const second = PouchPlannedItem(
      id: 'second-goal',
      description: 'Bicycle',
      amount: 5000,
      category: 'other',
      kind: 'goal',
      date: '2024-03-01',
      status: 'pending',
      paidDate: null,
      purchaseId: null,
    );
    final bridge = TestBridge()..forecastTargets = [target, second];
    await tester.pumpWidget(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: records(plannedItems: [target, second]),
        initialStrings: strings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-planned')));
    await settleApp(tester);
    await tester.tap(
      find.widgetWithText(ChoiceChip, strings.text('navSavings')),
    );
    await settleApp(tester);
    final shortcut = find.byKey(const ValueKey('goal-forecast-second-goal'));
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await settleApp(tester);
    final targetPicker = find
        .byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == strings.text('forecastSelect'),
        )
        .first;
    expect(
      tester.widget<DropdownButtonFormField<String>>(targetPicker).initialValue,
      second.id,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('nav-insights')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Reports load the current month without an extra action', (
    tester,
  ) async {
    final strings = localizedStrings['en']!;
    final bridge = SetupBridge();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(),
        home: Scaffold(
          body: ReportsScreen(
            bridge: bridge,
            snapshot: records(),
            strings: strings,
            today: '2024-01-10',
          ),
        ),
      ),
    );
    await settleApp(tester);
    expect(bridge.reportCalls, 1);
    expect(find.text(strings.text('reportEmpty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
