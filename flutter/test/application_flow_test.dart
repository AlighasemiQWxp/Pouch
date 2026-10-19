import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pouch/core/app_strings.dart';
import 'package:pouch/core/pouch_bridge.dart';
import 'package:pouch/core/pouch_models.dart';
import 'package:pouch/main.dart';
import 'package:pouch/features/budget_plan/period_controls.dart';
import 'package:pouch/core/pouch_theme.dart';
import 'package:pouch/features/forecast/financial_forecast_screen.dart';
import 'package:pouch/widgets/pouch_period_selector.dart';

const past = PouchPeriod(
  'BP-001',
  '2024-01-01',
  '2024-01-07',
  '2023-12-31',
  '2024-01-08',
  'weekly',
  0,
  'gregory',
  '2024-01-01',
  status: 'closed',
  name: 'P-17A2C3D4',
);
const active = PouchPeriod(
  'BP-002',
  '2024-01-08',
  '2024-01-14',
  '2024-01-07',
  '2024-01-15',
  'weekly',
  0,
  'gregory',
  '2024-01-08',
  name: 'P-58E6F7A8',
);
const target = PouchPlannedItem(
  id: 'goal',
  description: 'A savings goal',
  amount: 1000,
  category: 'other',
  kind: 'goal',
  date: '2024-02-01',
  status: 'pending',
  paidDate: null,
  purchaseId: null,
);
PouchSnapshot records({
  bool empty = false,
  bool targets = false,
  List<PouchDay> days = const [],
  List<PouchPlannedItem> plannedItems = const [],
  List<PouchBudgetPlan> savingsPlans = const [],
  List<PouchIncome> receivedIncome = const [],
  List<PouchExpectedIncome> expectedIncome = const [],
  int revision = 1,
  String language = 'en',
}) => PouchSnapshot(
  revision: revision,
  recovered: false,
  imported: false,
  startDate: '2024-01-01',
  preferences: PouchPreferences(
    country: 'canada',
    currency: 'CAD',
    language: language,
    calendar: 'gregory',
    weekStart: 0,
  ),
  income: receivedIncome,
  expectedIncome: expectedIncome,
  plans: savingsPlans,
  currentPlan: const PouchBudgetPlan(
    periodId: 'BP-002',
    effective: '2024-01-08',
    savings: 0,
  ),
  currentPeriod: empty ? null : active,
  periods: empty ? const [] : const [past, active],
  essentials: const [],
  incomeDays: const [],
  days: days,
  planned: targets ? const [target] : plannedItems,
);

class TestBridge extends PouchBridge {
  final requestedDates = <String>[];
  String? addedDate;
  final purchases = <String, List<PouchPurchase>>{};
  int revision = 1;
  bool rejectPurchases = false;
  bool rejectPlans = false;

  @override
  Future<PouchSnapshot> addPurchase({
    required String id,
    required String date,
    required String description,
    required String amount,
    required String category,
  }) async {
    if (rejectPurchases) throw StateError('Invalid amount');
    addedDate = date;
    purchases
        .putIfAbsent(date, () => [])
        .add(
          PouchPurchase(
            id: id,
            description: description,
            amount: 100,
            category: category,
            fundedByGoal: false,
          ),
        );
    return records(
      revision: ++revision,
      days: [
        for (final entry in purchases.entries) PouchDay(entry.key, entry.value),
      ],
    );
  }

  final plans = <String, PouchPlannedItem>{};
  final savingsPlans = <PouchBudgetPlan>[];
  final receivedIncome = <PouchIncome>[];
  final expectedIncome = <PouchExpectedIncome>[];
  final requestedPeriods = <String?>[];
  List<PouchBudgetPlan>? _previousSavingsPlans;
  bool rejectSavings = false;

  @override
  Future<PouchSnapshot> saveBudgetPlan({
    required String periodId,
    required String effective,
    required String savings,
  }) async {
    if (rejectSavings) throw StateError('Invalid amount');
    savingsPlans.removeWhere((plan) => plan.effective == effective);
    savingsPlans.add(
      PouchBudgetPlan(
        periodId: periodId,
        effective: effective,
        savings: (double.parse(savings.replaceAll(',', '')) * 100).round(),
      ),
    );
    return currentRecords();
  }

  @override
  Future<PouchSnapshot> removeBudgetPlan(String effective) async {
    _previousSavingsPlans = List.of(savingsPlans);
    savingsPlans.removeWhere((plan) => plan.effective == effective);
    return currentRecords();
  }

  @override
  Future<PouchSnapshot> undoLastChange() async {
    savingsPlans
      ..clear()
      ..addAll(_previousSavingsPlans!);
    _previousSavingsPlans = null;
    return currentRecords();
  }

  @override
  Future<PouchSnapshot> scheduleIncome({
    required String id,
    required String date,
    required String amount,
    String? periodId,
  }) async {
    expectedIncome.add(
      PouchExpectedIncome(
        id,
        date,
        (double.parse(amount.replaceAll(',', '')) * 100).round(),
        periodId: periodId,
      ),
    );
    return currentRecords();
  }

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
    receivedIncome.add(
      PouchIncome(
        id,
        date,
        (double.parse(amount.replaceAll(',', '')) * 100).round(),
        periodId: periodId,
      ),
    );
    if (expected) expectedIncome.removeWhere((item) => item.id == id);
    return currentRecords();
  }

  String? paidDate;
  int paymentCount = 0;

  PouchSnapshot currentRecords() => records(
    revision: ++revision,
    plannedItems: plans.values.toList(),
    savingsPlans: List.of(savingsPlans),
    receivedIncome: List.of(receivedIncome),
    expectedIncome: List.of(expectedIncome),
    days: [
      for (final entry in purchases.entries)
        PouchDay(entry.key, List.of(entry.value)),
    ],
  );

  @override
  Future<String> calendarDate({
    required int year,
    required int month,
    required int day,
    required String calendar,
  }) async =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  Future<PouchSnapshot> savePlanned({
    required String id,
    required String description,
    required String amount,
    required String category,
    required String kind,
    required String date,
    String? periodId,
  }) async {
    if (rejectPlans) throw StateError('Invalid amount');
    plans[id] = PouchPlannedItem(
      id: id,
      periodId: periodId,
      description: description,
      amount: 100,
      category: category,
      kind: kind,
      date: date,
      status: 'pending',
      paidDate: null,
      purchaseId: null,
    );
    return currentRecords();
  }

  @override
  Future<PouchSnapshot> removePlanned(String id) async {
    plans.remove(id);
    return currentRecords();
  }

  @override
  Future<PouchSnapshot> markPlannedPaid({
    required String planId,
    required String purchaseId,
    required String paidDate,
    required String amount,
  }) async {
    paymentCount++;
    this.paidDate = paidDate;
    final item = plans[planId]!;
    plans[planId] = PouchPlannedItem(
      id: item.id,
      description: item.description,
      amount: item.amount,
      category: item.category,
      kind: item.kind,
      date: item.date,
      status: 'paid',
      paidDate: paidDate,
      purchaseId: purchaseId,
      periodId: item.periodId,
    );
    purchases
        .putIfAbsent(paidDate, () => [])
        .add(
          PouchPurchase(
            id: purchaseId,
            description: item.description,
            amount: item.amount,
            category: item.category,
            fundedByGoal: false,
          ),
        );
    return currentRecords();
  }

  final personalPeriods = <String?>[];
  final standardDates = <String>[];
  @override
  Future<PouchBudgetSummary> budgetSummary(
    String date, {
    String? periodId,
  }) async {
    requestedDates.add(date);
    requestedPeriods.add(periodId);
    return PouchBudgetSummary(
      date: date,
      periodEnd: '2024-01-14',
      daysRemaining: 5,
      carry: 100,
      daily: 100,
      spent: 0,
      remaining: 500,
      income: 400,
      requiredExpenses: 0,
      savings: 0,
      funds: 500,
      reserved: 0,
      recommendation: 100,
      shortfall: 0,
    );
  }

  @override
  Future<PouchPeriodView> periodView(String date) async {
    final period = date == past.start ? past : active;
    final applicablePlans =
        savingsPlans
            .where(
              (plan) =>
                  plan.periodId == period.id &&
                  plan.effective.compareTo(date) <= 0,
            )
            .toList()
          ..sort((a, b) => a.effective.compareTo(b.effective));
    return PouchPeriodView(
      period,
      applicablePlans.isEmpty
          ? PouchBudgetPlan(
              periodId: period.id,
              effective: period.start,
              savings: 0,
            )
          : applicablePlans.last,
      await budgetSummary(period.start, periodId: period.id),
      receivedIncome.where((item) => item.periodId == period.id).toList(),
      expectedIncome.where((item) => item.periodId == period.id).toList(),
      0,
      const [],
      targets: const [target],
    );
  }

  @override
  Future<PouchFinancialForecast> financialForecast(
    String asOf,
    String selectedId, {
    bool recommended = false,
    bool incomeRequired = false,
    String? periodId,
  }) async {
    personalPeriods.add(periodId);
    return const PouchFinancialForecast(
      controllableSpending: 0,
      essentialExpenses: 0,
      configuredSavings: 0,
      extraDays: null,
      fasterDays: null,
      contribution: 0,
      periodIncome: 0,
      dailyAllowance: 10,
      requiredIncome: null,
      dailyLimit: 10,
      periodSaving: null,
      incomeGap: null,
      spendingReduction: 0,
      allocated: 0,
      remaining: 1000,
      completionDays: null,
      completionDate: null,
      onTrack: false,
      overdue: false,
      cycleDays: 7,
    );
  }

  @override
  Future<List<PouchEconomicCountry>> economicCountries() async => const [];
  @override
  Future<PouchStandardForecast> standardForecast(
    String asOf,
    String selectedId,
    String country,
  ) async {
    standardDates.add(asOf);
    return PouchStandardForecast.fromJson({
      'country': country,
      'status': 'ready',
      'customized': false,
      'needsRefresh': false,
      'cacheWarning': false,
      'currency': 'CAD',
      'remaining': 1000,
      'observations': <dynamic>[],
    });
  }

  @override
  Future<PouchCalendarMonth> calendarMonth(
    String date,
    String calendar,
    int offset,
  ) async {
    final input = DateTime.parse(date);
    final first = DateTime(input.year, input.month + offset, 1);
    return PouchCalendarMonth(
      startDate:
          '${first.year.toString().padLeft(4, '0')}-${first.month.toString().padLeft(2, '0')}-01',
      year: first.year,
      month: first.month,
      dayCount: DateTime(first.year, first.month + 1, 0).day,
      firstWeekday: first.weekday % 7,
    );
  }
}

Future<void> settleApp(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> choosePeriod(
  WidgetTester tester,
  String id, {
  Finder? selector,
}) async {
  final field = find.descendant(
    of: selector ?? find.byType(PouchPeriodSelector).first,
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await settleApp(tester);
  final choice = find
      .ancestor(
        of: find.byKey(ValueKey('period-choice-$id')),
        matching: find.byType(InkWell),
      )
      .hitTestable();
  expect(choice, findsOneWidget);
  await tester.tap(choice);
  await settleApp(tester);
}

class PeriodManagementBridge extends TestBridge {
  String? removedPeriod;
  String? editedPeriod;

  @override
  Future<PouchSnapshot> removePeriod(String id) async {
    removedPeriod = id;
    return records(empty: true);
  }

  @override
  Future<PouchSnapshot> savePeriod({
    String? id,
    required String start,
    required String kind,
    int customDays = 7,
    String? through,
  }) async {
    editedPeriod = id;
    return records();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStrings englishStrings;
  late AppStrings persianStrings;
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fa');
    englishStrings = await AppStrings.load('en');
    persianStrings = await AppStrings.load('fa');
  });
  test(
    'English and Persian localization keys and placeholders match',
    () async {
      final en = jsonDecode(
        await rootBundle.loadString('assets/l10n/strings_en.json'),
      ) as Map<String, dynamic>;
      final fa = jsonDecode(
        await rootBundle.loadString('assets/l10n/strings_fa.json'),
      ) as Map<String, dynamic>;
      expect(en.keys.toSet(), fa.keys.toSet());
      for (final key in en.keys) {
        final pattern = RegExp(r'\{([^}]+)\}');
        expect(
          pattern.allMatches(en[key] as String).map((m) => m[1]).toSet(),
          pattern.allMatches(fa[key] as String).map((m) => m[1]).toSet(),
          reason: key,
        );
      }
    },
  );
  testWidgets('Daily purchases follow the chosen day across navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge = TestBridge();
    await tester.pumpWidget(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: records(),
        initialStrings: englishStrings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('previous-day')));
    await settleApp(tester);
    expect(bridge.requestedDates, contains('2024-01-09'));
    final add = find.text(englishStrings.text('addPurchase'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await settleApp(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Yesterday coffee');
    await tester.enterText(find.byType(TextField).at(1), '1');
    await tester.tap(find.text(englishStrings.text('save')));
    await settleApp(tester);
    expect(bridge.addedDate, '2024-01-09');
    expect(find.text('Yesterday coffee'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-budget')));
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-today')));
    await settleApp(tester);
    expect(bridge.requestedDates, contains('2024-01-09'));
    expect(find.text('Yesterday coffee'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-day')));
    await settleApp(tester);
    expect(bridge.requestedDates, contains('2024-01-10'));
    expect(find.text('Yesterday coffee'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-day')))
          .onPressed,
      isNotNull,
    );
    final history = find.text(englishStrings.text('purchaseHistory'));
    await tester.ensureVisible(history);
    await tester.tap(history);
    await settleApp(tester);
    expect(find.text('Yesterday coffee'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Future calendar expenses stay planned until a payment is recorded',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bridge = TestBridge();
      final strings = englishStrings;
      await tester.pumpWidget(
        PouchApplication(
          bridge: bridge,
          initialSnapshot: records(),
          initialStrings: strings,
          initialToday: '2024-01-10',
          initialThemeStyle: 'classic',
        ),
      );
      await settleApp(tester);
      await tester.tap(find.byKey(const ValueKey('select-day')));
      await settleApp(tester);
      await tester.tap(find.widgetWithText(TextButton, '12'));
      await settleApp(tester);
      expect(bridge.requestedDates, contains('2024-01-12'));
      expect(find.text(strings.text('futureAllowance')), findsOneWidget);
      final add = find.text(strings.text('addPlannedExpense'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settleApp(tester);
      await tester.enterText(find.byType(TextField).at(0), 'Friday groceries');
      await tester.enterText(find.byType(TextField).at(1), '1');
      await tester.tap(find.text(strings.text('save')));
      await settleApp(tester);
      final id = bridge.plans.keys.single;
      expect(bridge.plans[id]!.date, '2024-01-12');
      expect(bridge.plans[id]!.status, 'pending');
      expect(bridge.purchases, isEmpty);
      expect(bridge.addedDate, isNull);
      await tester.tap(find.byKey(const ValueKey('nav-planned')));
      await settleApp(tester);
      expect(find.text('Friday groceries'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-today')));
      await settleApp(tester);
      final pay = find.byKey(ValueKey('pay-$id'));
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await settleApp(tester);
      expect(bridge.paymentCount, 0);
      await tester.tap(find.text(strings.text('confirmPayment')));
      await settleApp(tester);
      expect(bridge.paymentCount, 1);
      expect(bridge.paidDate, '2024-01-10');
      expect(bridge.plans[id]!.status, 'paid');
      expect(find.byKey(ValueKey('daily-plan-$id')), findsNothing);
      final back = find.text(strings.text('backToToday'));
      await tester.ensureVisible(back);
      await tester.tap(back);
      await settleApp(tester);
      expect(find.text('Friday groceries'), findsOneWidget);
      expect(bridge.purchases.values.expand((items) => items), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Every savings entry can be cancelled, deleted and restored', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge = TestBridge();
    for (final date in ['2024-01-08', '2024-01-10', '2024-01-12']) {
      bridge.savingsPlans.add(
        PouchBudgetPlan(periodId: active.id, effective: date, savings: 10000),
      );
    }
    await tester.pumpWidget(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: bridge.currentRecords(),
        initialStrings: englishStrings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-budget')));
    await settleApp(tester);
    final history = find.text(englishStrings.text('planHistory'));
    await tester.ensureVisible(history);
    await tester.tap(history);
    await settleApp(tester);
    for (final date in ['2024-01-08', '2024-01-10', '2024-01-12']) {
      final remove = find.byKey(ValueKey('delete-savings-$date'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await settleApp(tester);
      expect(
        find.text(englishStrings.text('deleteSavingsHint')),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(TextButton, englishStrings.text('cancel')),
      );
      await settleApp(tester);
      expect(bridge.savingsPlans, hasLength(3));
      await tester.tap(remove);
      await settleApp(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, englishStrings.text('delete')),
      );
      await settleApp(tester);
      expect(bridge.savingsPlans, hasLength(2));
      expect(find.byKey(ValueKey('savings-plan-$date')), findsNothing);
      expect(find.byKey(const ValueKey('pouch-coin-burst')), findsNothing);
      await tester.tap(find.text(englishStrings.text('undo')));
      await settleApp(tester);
      expect(bridge.savingsPlans, hasLength(3));
      expect(find.byKey(ValueKey('savings-plan-$date')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Coins follow successful receipts and savings increases', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge = TestBridge();
    await tester.pumpWidget(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: records(),
        initialStrings: englishStrings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-budget')));
    await settleApp(tester);
    await tester.enterText(find.byType(TextField).first, '100');
    final receive = find.text(englishStrings.text('addIncome'));
    await tester.ensureVisible(receive);
    await tester.tap(receive);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(bridge.receivedIncome, hasLength(1));
    expect(find.byKey(const ValueKey('pouch-coin-burst')), findsOneWidget);
    await settleApp(tester);
    expect(find.byKey(const ValueKey('pouch-coin-burst')), findsNothing);

    final savings = find.byType(TextField).at(1);
    await tester.ensureVisible(savings);
    await tester.enterText(savings, '50');
    final save = find.text(englishStrings.text('savePlan'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('pouch-coin-burst')), findsOneWidget);
    await settleApp(tester);

    for (final amount in ['50', '25']) {
      await tester.enterText(savings, amount);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('pouch-coin-burst')), findsNothing);
      await settleApp(tester);
    }
    bridge.rejectSavings = true;
    await tester.enterText(savings, '90');
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('pouch-coin-burst')), findsNothing);
    expect(bridge.savingsPlans.single.savings, 2500);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final entry in ['daily', 'expense', 'goal']) {
    testWidgets('Coins follow successful $entry saves only', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bridge = TestBridge();
      await tester.pumpWidget(
        PouchApplication(
          bridge: bridge,
          initialSnapshot: records(),
          initialStrings: englishStrings,
          initialToday: '2024-01-10',
          initialThemeStyle: 'classic',
        ),
      );
      await settleApp(tester);
      if (entry != 'daily') {
        await tester.tap(find.byKey(const ValueKey('nav-planned')));
        await settleApp(tester);
        if (entry == 'goal') {
          await tester.tap(
            find.widgetWithText(ChoiceChip, englishStrings.text('navSavings')),
          );
          await settleApp(tester);
        }
      }
      final label = switch (entry) {
        'daily' => 'addPurchase',
        'goal' => 'addGoal',
        _ => 'addPlannedExpense',
      };
      final add = find.text(englishStrings.text(label));
      final burst = find.byKey(const ValueKey('pouch-coin-burst'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settleApp(tester);
      expect(burst, findsNothing);
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'A new $entry');
      await tester.enterText(fields.at(1), '10');
      await tester.tap(find.text(englishStrings.text('save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(burst, findsOneWidget);
      await settleApp(tester);
      expect(burst, findsNothing);
      final savedCount = entry == 'daily'
          ? bridge.purchases.values.expand((items) => items).length
          : bridge.plans.length;
      expect(savedCount, 1);

      bridge.rejectPurchases = true;
      bridge.rejectPlans = true;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settleApp(tester);
      await tester.enterText(fields.at(0), 'Rejected $entry');
      await tester.enterText(fields.at(1), '10');
      await tester.tap(find.text(englishStrings.text('save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(burst, findsNothing);
      expect(
        entry == 'daily'
            ? bridge.purchases.values.expand((items) => items).length
            : bridge.plans.length,
        1,
      );
      await settleApp(tester);

      await tester.ensureVisible(add);
      await tester.tap(add);
      await settleApp(tester);
      await tester.tap(
        find.widgetWithText(TextButton, englishStrings.text('cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(burst, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  testWidgets('Income calendar saves dates and independent period choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge = TestBridge();
    await tester.pumpWidget(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: records(),
        initialStrings: englishStrings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    expect(
      find.text(
        englishStrings.text('periodCalculationHint', {
          'period': active.displayName,
        }),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('nav-budget')));
    await settleApp(tester);
    final day = find.byKey(const ValueKey('income-date-2024-01-06'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.enterText(find.byType(TextField).first, '100');
    final save = find.text(englishStrings.text('addIncome'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(bridge.receivedIncome.single.date, '2024-01-06');
    expect(bridge.receivedIncome.single.periodId, active.id);
    expect(find.byKey(const ValueKey('pouch-coin-burst')), findsOneWidget);
    expect(find.text(englishStrings.text('incomeDestination')), findsNothing);
    await settleApp(tester);

    await choosePeriod(tester, past.id);
    final future = find.byKey(const ValueKey('income-date-2024-01-12'));
    await tester.ensureVisible(future);
    await tester.tap(future);
    await tester.enterText(find.byType(TextField).first, '25');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(bridge.expectedIncome.single.date, '2024-01-12');
    expect(bridge.expectedIncome.single.periodId, past.id);
    expect(bridge.receivedIncome, hasLength(1));
    expect(find.byKey(const ValueKey('pouch-coin-burst')), findsOneWidget);
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-today')));
    await settleApp(tester);
    expect(
      find.text(
        englishStrings.text('periodCalculationHint', {
          'period': past.displayName,
        }),
      ),
      findsOneWidget,
    );
    expect(bridge.requestedPeriods.last, past.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 30)));

  for (final kind in ['expense', 'goal']) {
    testWidgets('New $kind can be assigned to a period outside its date', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bridge = TestBridge();
      await tester.pumpWidget(
        PouchApplication(
          bridge: bridge,
          initialSnapshot: records(),
          initialStrings: englishStrings,
          initialToday: '2024-01-10',
          initialThemeStyle: 'classic',
        ),
      );
      await settleApp(tester);
      await tester.tap(find.byKey(const ValueKey('nav-planned')));
      await settleApp(tester);
      if (kind == 'goal') {
        await tester.tap(
          find.widgetWithText(ChoiceChip, englishStrings.text('navSavings')),
        );
        await settleApp(tester);
      }
      await tester.tap(
        find.text(
          englishStrings.text(kind == 'goal' ? 'addGoal' : 'addPlannedExpense'),
        ),
      );
      await settleApp(tester);
      final dialog = find.byType(AlertDialog);
      final selector = find.descendant(
        of: dialog,
        matching: find.byType(PouchPeriodSelector),
      );
      expect(
        tester.widget<PouchPeriodSelector>(selector).selectedId,
        active.id,
      );
      await choosePeriod(tester, past.id, selector: selector);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'Assigned $kind');
      await tester.enterText(fields.at(1), '10');
      final due = find.descendant(of: dialog, matching: find.byType(ListTile));
      await tester.ensureVisible(due);
      await tester.tap(due);
      await settleApp(tester);
      await tester.tap(find.widgetWithText(TextButton, '12'));
      await settleApp(tester);
      await tester.tap(find.text(englishStrings.text('save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(bridge.plans.values.single.periodId, past.id);
      expect(bridge.plans.values.single.date, '2024-01-12');
      expect(find.byKey(const ValueKey('pouch-coin-burst')), findsOneWidget);
      await settleApp(tester);
      expect(find.text('Assigned $kind'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  testWidgets('About is accessed from Settings and returns there', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      PouchApplication(
        bridge: TestBridge(),
        initialSnapshot: records(),
        initialStrings: englishStrings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    expect(find.byKey(const ValueKey('nav-about')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-preferences')));
    await settleApp(tester);
    final about = find.text(englishStrings.text('navAbout'));
    await tester.ensureVisible(about);
    await tester.tap(about);
    await settleApp(tester);
    expect(find.byType(BackButton), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('nav-preferences')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byType(BackButton));
    await settleApp(tester);
    expect(find.byType(BackButton), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['en', 'fa']) {
    testWidgets(
      'Daily summary and future expenses fit enlarged $language text',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 900));
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(() async {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
        });
        final strings = language == 'fa' ? persianStrings : englishStrings;
        await tester.pumpWidget(
          PouchApplication(
            bridge: TestBridge(),
            initialSnapshot: records(language: language),
            initialStrings: strings,
            initialToday: '2024-01-10',
            initialThemeStyle: 'classic',
          ),
        );
        await settleApp(tester);
        final nextDay = find.byKey(const ValueKey('next-day'));
        await Scrollable.ensureVisible(tester.element(nextDay), alignment: 0.5);
        await settleApp(tester);
        await tester.tap(nextDay);
        await settleApp(tester);
        final details = find.text(strings.text('budgetBreakdown'));
        await Scrollable.ensureVisible(tester.element(details), alignment: 0.5);
        await settleApp(tester);
        await tester.tap(details);
        await settleApp(tester);
        expect(find.text(strings.text('protectedSavings')), findsOneWidget);
        expect(find.text(strings.text('savingsSetAsideHint')), findsOneWidget);
        final add = find.text(strings.text('addPlannedExpense'));
        await Scrollable.ensureVisible(tester.element(add), alignment: 0.5);
        await settleApp(tester);
        await tester.tap(add);
        await settleApp(tester);
        expect(find.text(strings.text('plannedEntryHint')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  }

  testWidgets('Viewing a historical plan leaves Today tied to today', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge = TestBridge();
    final strings = englishStrings;
    await tester.pumpWidget(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: records(),
        initialStrings: strings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    expect(bridge.requestedDates, contains('2024-01-10'));
    await tester.tap(find.byKey(const ValueKey('nav-budget')));
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('period-history')));
    await settleApp(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('select-BP-001')));
    await tester.tap(find.byKey(const ValueKey('select-BP-001')));
    await settleApp(tester);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('select-BP-001')))
          .selected,
      isTrue,
    );
    bridge.requestedDates.clear();
    await tester.tap(find.byKey(const ValueKey('nav-today')));
    await settleApp(tester);
    expect(bridge.requestedDates, contains('2024-01-10'));
    expect(bridge.requestedDates, isNot(contains('2024-01-01')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('First period setup opens a planning horizon form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final strings = englishStrings;
    await tester.pumpWidget(
      PouchApplication(
        bridge: TestBridge(),
        initialSnapshot: records(empty: true),
        initialStrings: strings,
        initialToday: '2024-01-10',
        initialThemeStyle: 'classic',
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-budget')));
    await settleApp(tester);
    await tester.tap(find.text(strings.text('createPeriod')).last);
    await settleApp(tester);
    expect(find.text('How long should this budget last?'), findsOneWidget);
    expect(find.text(strings.text('periodStart')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets(
    'Personal period changes preserve the Standard Forecast request basis',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final strings = englishStrings;
      final bridge = TestBridge();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPouchTheme(),
          home: Scaffold(
            body: FinancialForecastScreen(
              bridge: bridge,
              snapshot: records(targets: true),
              strings: strings,
              today: '2024-01-10',
              run: (_) async => false,
              onOpenPlanned: () {},
            ),
          ),
        ),
      );
      await settleApp(tester);
      final comparison = find.text(strings.text('forecastCompareCountry'));
      await tester.ensureVisible(comparison);
      await tester.tap(comparison);
      await settleApp(tester);
      expect(bridge.standardDates, ['2024-01-10']);
      final periodPicker = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText ==
                strings.text('personalForecastPeriod'),
      );
      expect(periodPicker, findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(periodPicker)
            .initialValue,
        active.id,
      );
      await tester.ensureVisible(periodPicker);
      await tester.tap(periodPicker);
      await settleApp(tester);
      final previousPeriod = find
          .ancestor(
            of: find.byKey(const ValueKey('period-choice-BP-001')),
            matching: find.byType(InkWell),
          )
          .hitTestable();
      expect(previousPeriod, findsOneWidget);
      await tester.tap(previousPeriod);
      await settleApp(tester);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(periodPicker)
            .initialValue,
        past.id,
      );
      expect(bridge.personalPeriods, contains('BP-001'));
      expect(bridge.standardDates, ['2024-01-10']);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets('Period controls edit an existing period and confirm deletion', (
    tester,
  ) async {
    final bridge = PeriodManagementBridge();
    String? selected;
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PeriodControls(
              bridge: bridge,
              snapshot: records(),
              strings: englishStrings,
              today: '2024-01-10',
              view: null,
              run: (operation) async {
                await operation();
                return true;
              },
              select: (date) => selected = date,
            ),
          ),
        ),
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('edit-period')));
    await settleApp(tester);
    expect(find.text(englishStrings.text('editPeriod')), findsWidgets);
    await tester.tap(find.text(englishStrings.text('saveChanges')));
    await settleApp(tester);
    expect(bridge.editedPeriod, active.id);
    expect(selected, active.start);
    await tester.tap(find.byKey(const ValueKey('delete-period')));
    await settleApp(tester);
    expect(bridge.removedPeriod, isNull);
    await tester.tap(find.text(englishStrings.text('cancel')));
    await settleApp(tester);
    expect(bridge.removedPeriod, isNull);
    await tester.tap(find.byKey(const ValueKey('delete-period')));
    await settleApp(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-period')));
    await settleApp(tester);
    expect(bridge.removedPeriod, active.id);
    expect(selected, past.start);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
