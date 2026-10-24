import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pouch/core/app_strings.dart';
import 'package:pouch/core/pouch_bridge.dart';
import 'package:pouch/core/pouch_models.dart';
import 'package:pouch/core/pouch_theme.dart';
import 'package:pouch/features/dashboard/dashboard_charts.dart';
import 'package:pouch/features/dashboard/dashboard_models.dart';
import 'package:pouch/features/dashboard/dashboard_screen.dart';
import 'package:pouch/widgets/pouch_period_selector.dart';

const _period = PouchPeriod(
  'BP-001',
  '2024-01-01',
  '2024-01-31',
  '2023-12-31',
  '2024-02-01',
  'monthly',
  0,
  'gregory',
  '2024-01-01',
  name: 'January',
);
const _other = PouchPeriod(
  'BP-002',
  '2024-02-01',
  '2024-02-29',
  '2024-01-31',
  '2024-03-01',
  'monthly',
  0,
  'gregory',
  '2024-02-01',
  name: 'February',
);

PouchSnapshot _snapshot(
  String language, {
  int revision = 1,
  PouchPeriod? currentPeriod = _period,
  List<PouchPeriod> periods = const [_period, _other],
}) => PouchSnapshot(
  revision: revision,
  recovered: false,
  imported: false,
  startDate: '2024-01-01',
  preferences: PouchPreferences(
    country: 'canada',
    currency: 'CAD',
    language: language,
    calendar: language == 'fa' ? 'persian' : 'gregory',
    weekStart: 6,
  ),
  income: const [],
  expectedIncome: const [],
  plans: const [],
  currentPlan: const PouchBudgetPlan(
    periodId: 'BP-001',
    effective: '2024-01-01',
    savings: 0,
  ),
  currentPeriod: currentPeriod,
  periods: periods,
  essentials: const [],
  incomeDays: const [],
  days: const [],
  planned: const [],
);

DashboardData _data({
  String from = '2024/01/01',
  bool empty = false,
  bool future = false,
  int free = 7000,
  int? assignedIncome,
  bool noSpending = false,
}) {
  var income = 10000;
  var expenses = 1000;
  if (empty) income = 0;
  if (empty || noSpending) expenses = 0;
  return DashboardData.fromJson({
    'fromLabel': from,
    'throughLabel': '2024/01/31',
    'asOfLabel': '2024/01/15',
    'income': income,
    'assignedIncome': assignedIncome,
    'expenses': expenses,
    'net': income - expenses,
    'cash': 9000,
    'free': free,
    'protectedSavings': 2000,
    'reserved': 0,
    'contributions': 2000,
    'releases': 0,
    'hasActivity': !empty,
    'futureOnly': future,
    'goalCount': 1,
    'comparisonCount': 1,
    'categories': empty || noSpending
        ? []
        : [
            {'key': 'food', 'amount': 1000},
          ],
    'spending': empty || noSpending
        ? []
        : [
            {'key': 'dashboardOtherSpending', 'amount': 1000},
          ],
    'allocation': [
      {'key': 'dashboardAvailable', 'amount': 7000},
      {'key': 'protectedSavings', 'amount': 2000},
    ],
    'points': future
        ? []
        : [
            {
              'label': from,
              'endLabel': from,
              'income': income,
              'expenses': expenses,
              'contributions': 2000,
              'releases': 0,
              'cash': 9000,
              'savings': 2000,
            },
          ],
    'progress': [
      {
        'key': 'dashboardUtilization',
        'name': '',
        'amount': 1000,
        'target': 8000,
        'basisPoints': 1250,
      },
    ],
    'goals': [
      {
        'key': 'goal',
        'name': 'Bicycle',
        'amount': 2000,
        'target': 4000,
        'basisPoints': 5000,
      },
    ],
    'comparisons': [
      {
        'name': 'January',
        'from': from,
        'through': '2024/01/15',
        'income': income,
        'expenses': expenses,
        'planned': 1000,
        'paid': 1000,
        'savingsTarget': 2000,
        'savings': 2000,
      },
    ],
  });
}

class _Bridge extends PouchBridge {
  final requests = <DashboardSelection>[];
  final pending = <Completer<DashboardData>>[];
  bool delayed = false;
  bool fail = false;
  DashboardData? response;

  @override
  Future<DashboardData> dashboard(DashboardSelection selection) {
    requests.add(selection);
    if (fail) return Future.error(StateError('Unavailable'));
    if (!delayed) return Future.value(response ?? _data());
    final completer = Completer<DashboardData>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<(int, int, int)> dateParts(String date, String calendar) async =>
      (1402, 10, 25);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final strings = <String, AppStrings>{};
  setUpAll(() async {
    await initializeDateFormatting();
    for (final language in ['en', 'fa']) {
      strings[language] = await AppStrings.load(language);
    }
  });

  Future<void> show(
    WidgetTester tester,
    _Bridge bridge, {
    String language = 'en',
    String theme = 'classic',
    double width = 1280,
    double scale = 1,
    PouchSnapshot? snapshot,
    String today = '2024-01-15',
    ValueChanged<String>? onSharedPeriod,
    VoidCallback? onOpenToday,
    VoidCallback? onOpenBudget,
    VoidCallback? onOpenPlans,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(theme),
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: PouchPeriodScope(
                periodId: 'BP-002',
                onChanged: onSharedPeriod ?? (_) {},
                child: DashboardScreen(
                  bridge: bridge,
                  snapshot: snapshot ?? _snapshot(language),
                  strings: strings[language]!,
                  today: today,
                  onOpenToday: onOpenToday ?? () {},
                  onOpenBudget: onOpenBudget ?? () {},
                  onOpenPlans: onOpenPlans ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> selectRange(WidgetTester tester, String mode) async {
    final selector = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final option = find.text(strings['en']!.text('dashboardFilter_$mode')).last;
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> selectPeriod(WidgetTester tester, String id) async {
    final selector = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final option = find
        .ancestor(
          of: find.byKey(ValueKey('dashboard-period-choice-$id')),
          matching: find.byType(InkWell),
        )
        .hitTestable();
    expect(option, findsOneWidget);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  for (final language in ['en', 'fa']) {
    for (final width in [320.0, 700.0, 1280.0]) {
      for (final theme in ['classic', 'ocean', 'forest']) {
        testWidgets(
          'Dashboard fits $language $width $theme with enlarged text',
          (tester) async {
            await show(
              tester,
              _Bridge(),
              language: language,
              width: width,
              scale: 1.6,
              theme: theme,
            );
            expect(
              find.text(strings[language]!.text('dashboardTitle')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            expect(find.byType(DashboardChart), findsNothing);
            expect(find.byType(DashboardDonut), findsOneWidget);
            for (final section in [
              'activity',
              'balances',
              'budget',
              'savings',
            ]) {
              final details = find.byKey(
                ValueKey('dashboard-details-$section'),
              );
              await tester.ensureVisible(details);
              await tester.tap(details);
              await tester.pump(const Duration(milliseconds: 300));
              expect(tester.takeException(), isNull);
            }
            await tester.ensureVisible(find.byType(DashboardChart).last);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
              Directionality.of(tester.element(find.byType(DashboardScreen))),
              language == 'fa' ? TextDirection.rtl : TextDirection.ltr,
            );
          },
        );
      }
    }
  }

  testWidgets('Overview keeps details closed and shortcuts open their pages', (
    tester,
  ) async {
    var todayOpens = 0;
    var budgetOpens = 0;
    var plansOpens = 0;
    final bridge = _Bridge();
    await show(
      tester,
      bridge,
      onOpenToday: () => todayOpens++,
      onOpenBudget: () => budgetOpens++,
      onOpenPlans: () => plansOpens++,
    );
    expect(bridge.requests.single.mode, 'period');
    expect(bridge.requests.single.periodId, 'BP-001');
    expect(find.text(strings['en']!.text('dashboardFree')), findsOneWidget);
    expect(find.byType(DashboardChart), findsNothing);
    expect(find.byType(DashboardDonut), findsOneWidget);
    expect(find.text('Bicycle'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    for (final page in ['today', 'budget', 'plans']) {
      final shortcut = find.byKey(ValueKey('dashboard-open-$page'));
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pump();
    }
    expect(todayOpens, 1);
    expect(budgetOpens, 1);
    expect(plansOpens, 1);
    expect(bridge.requests, hasLength(1));
  });

  for (final manualMode in ['period', 'custom']) {
    testWidgets('Reopening forgets the manual $manualMode selection', (
      tester,
    ) async {
      final bridge = _Bridge();
      await show(tester, bridge);
      if (manualMode == 'period') {
        await selectPeriod(tester, _other.id);
        expect(bridge.requests.last.periodId, 'BP-002');
      } else {
        await selectRange(tester, 'custom');
        expect(bridge.requests.last.mode, 'custom');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await show(tester, bridge);
      expect(bridge.requests.last.mode, 'period');
      expect(bridge.requests.last.periodId, 'BP-001');
      expect(
        find.byKey(const ValueKey('dashboard-period-BP-001')),
        findsOneWidget,
      );
    });
  }

  testWidgets('Reopening uses the newly resolved Rust active period', (
    tester,
  ) async {
    final bridge = _Bridge();
    await show(tester, bridge);
    expect(bridge.requests.last.periodId, 'BP-001');
    await tester.pumpWidget(const SizedBox.shrink());
    await show(
      tester,
      bridge,
      snapshot: _snapshot('en', currentPeriod: _other),
      today: '2024-02-15',
    );
    expect(bridge.requests.last.mode, 'period');
    expect(bridge.requests.last.periodId, 'BP-002');
    expect(
      find.byKey(const ValueKey('dashboard-period-BP-002')),
      findsOneWidget,
    );
  });

  for (final today in ['2023-12-15', '2024-03-15']) {
    testWidgets('No active period on $today defaults to the calendar month', (
      tester,
    ) async {
      final bridge = _Bridge();
      await show(
        tester,
        bridge,
        snapshot: _snapshot('en', currentPeriod: null),
        today: today,
      );
      expect(bridge.requests.single.mode, 'monthly');
      expect(bridge.requests.single.anchor, today);
      expect(bridge.requests.single.periodId, isNull);
      expect(
        find.text(strings['en']!.text('dashboardNoActivePeriod')),
        findsOneWidget,
      );
      expect(find.text(strings['en']!.text('dashboardError')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'No saved periods explains the fallback and disables period mode',
    (tester) async {
      final bridge = _Bridge();
      await show(
        tester,
        bridge,
        snapshot: _snapshot('en', currentPeriod: null, periods: const []),
      );
      expect(bridge.requests.single.mode, 'monthly');
      expect(bridge.requests.single.periodId, isNull);
      expect(
        find.text(strings['en']!.text('dashboardNoActivePeriod')),
        findsOneWidget,
      );
      final selector = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('dashboard-range-monthly')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        selector.items!.singleWhere((item) => item.value == 'period').enabled,
        isFalse,
      );
    },
  );

  testWidgets('A saved period can be chosen without an active period', (
    tester,
  ) async {
    final bridge = _Bridge();
    var sharedChanges = 0;
    await show(
      tester,
      bridge,
      snapshot: _snapshot('en', currentPeriod: null),
      today: '2024-03-15',
      onSharedPeriod: (_) => sharedChanges++,
    );
    await selectRange(tester, 'period');
    expect(bridge.requests, hasLength(1));
    expect(
      find.text(strings['en']!.text('dashboardChoosePeriodHint')),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-balance')), findsNothing);
    expect(find.text(strings['en']!.text('dashboardError')), findsNothing);
    await show(
      tester,
      bridge,
      snapshot: _snapshot('en', revision: 2, currentPeriod: null),
      today: '2024-03-15',
      onSharedPeriod: (_) => sharedChanges++,
    );
    expect(bridge.requests, hasLength(1));
    expect(
      find.text(strings['en']!.text('dashboardChoosePeriodHint')),
      findsOneWidget,
    );
    await selectPeriod(tester, _period.id);
    expect(bridge.requests.last.mode, 'period');
    expect(bridge.requests.last.periodId, 'BP-001');
    expect(find.byKey(const ValueKey('dashboard-balance')), findsOneWidget);
    expect(
      find.text(strings['en']!.text('dashboardNoActivePeriod')),
      findsNothing,
    );
    expect(sharedChanges, 0);
    expect(
      PouchPeriodScope.maybeOf(tester.element(find.byType(DashboardScreen)))!
          .periodId,
      'BP-002',
    );
  });

  testWidgets('Snapshot refresh preserves a manual period or date range', (
    tester,
  ) async {
    final bridge = _Bridge();
    await show(tester, bridge);
    await selectPeriod(tester, _other.id);
    await show(tester, bridge, snapshot: _snapshot('en', revision: 2));
    expect(bridge.requests.last.mode, 'period');
    expect(bridge.requests.last.periodId, 'BP-002');
    await selectRange(tester, 'custom');
    final selection = bridge.requests.last;
    await show(
      tester,
      bridge,
      snapshot: _snapshot(
        'en',
        revision: 3,
        currentPeriod: null,
        periods: const [],
      ),
    );
    expect(bridge.requests.last.mode, 'custom');
    expect(bridge.requests.last.from, selection.from);
    expect(bridge.requests.last.through, selection.through);
    expect(bridge.requests.last.periodId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Removing the selected period uses the current period or month', (
    tester,
  ) async {
    final bridge = _Bridge();
    await show(tester, bridge);
    await selectPeriod(tester, _other.id);
    await show(
      tester,
      bridge,
      snapshot: _snapshot('en', revision: 2, periods: const [_period]),
    );
    expect(bridge.requests.last.mode, 'period');
    expect(bridge.requests.last.periodId, 'BP-001');
    await show(
      tester,
      bridge,
      snapshot: _snapshot(
        'en',
        revision: 3,
        currentPeriod: null,
        periods: const [],
      ),
    );
    expect(bridge.requests.last.mode, 'monthly');
    expect(bridge.requests.last.periodId, isNull);
    expect(
      find.text(strings['en']!.text('dashboardNoActivePeriod')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Details open on demand and retain accessible chart data', (
    tester,
  ) async {
    final bridge = _Bridge()..response = _data(assignedIncome: 15000);
    await show(tester, bridge);
    expect(
      find.text(strings['en']!.text('dashboardAssignedIncome')),
      findsNothing,
    );
    final activity = find.byKey(const ValueKey('dashboard-details-activity'));
    await tester.ensureVisible(activity);
    await tester.tap(activity);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardChart), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(
      find.text(strings['en']!.text('dashboardAssignedIncome')),
      findsOneWidget,
    );
    final dataToggle = find.text(strings['en']!.text('dashboardViewData'));
    await tester.ensureVisible(dataToggle);
    await tester.tap(dataToggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('100.00'), findsWidgets);
    final activityHeader = find
        .descendant(of: activity, matching: find.byType(ListTile))
        .first;
    await tester.ensureVisible(activityHeader);
    await tester.tap(activityHeader);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A shortfall stays visible in the main overview', (tester) async {
    final bridge = _Bridge()..response = _data(free: -2500);
    await show(tester, bridge);
    final balance = find.byKey(const ValueKey('dashboard-balance'));
    expect(
      find.descendant(
        of: balance,
        matching: find.text(strings['en']!.text('dashboardShortfall')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: balance, matching: find.textContaining('-')),
      findsWidgets,
    );
    expect(
      find.text(strings['en']!.text('dashboardDeficitHint')),
      findsOneWidget,
    );
    expect(find.byType(DashboardChart), findsNothing);
  });

  testWidgets('An income-only range avoids an empty spending chart', (
    tester,
  ) async {
    final bridge = _Bridge()..response = _data(noSpending: true);
    await show(tester, bridge);
    expect(
      find.text(strings['en']!.text('dashboardNoSpending')),
      findsOneWidget,
    );
    expect(find.byType(DashboardDonut), findsNothing);
  });

  testWidgets('Back to this month resets the local range only', (tester) async {
    final bridge = _Bridge();
    var sharedChanges = 0;
    await show(tester, bridge, onSharedPeriod: (_) => sharedChanges++);
    await selectRange(tester, 'yearly');
    final reset = find.byKey(const ValueKey('dashboard-reset-range'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(bridge.requests.last.mode, 'monthly');
    expect(bridge.requests.last.anchor, '2024-01-15');
    expect(sharedChanges, 0);
    expect(find.byKey(const ValueKey('dashboard-date-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-reset-range')), findsNothing);
  });

  testWidgets('All filters query independently of the shared period', (
    tester,
  ) async {
    final bridge = _Bridge();
    var sharedChanges = 0;
    await show(tester, bridge, onSharedPeriod: (_) => sharedChanges++);
    for (final mode in [
      'daily',
      'weekly',
      'monthly',
      'yearly',
      'custom',
      'period',
    ]) {
      await selectRange(tester, mode);
      expect(bridge.requests.last.mode, mode);
    }
    await selectPeriod(tester, _other.id);
    expect(bridge.requests.last.periodId, 'BP-002');
    expect(sharedChanges, 0);
  });

  testWidgets('A late response cannot replace the newly selected range', (
    tester,
  ) async {
    final bridge = _Bridge()..delayed = true;
    await show(tester, bridge);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await selectRange(tester, 'daily');
    bridge.pending[1].complete(_data(from: 'NEW RANGE'));
    await tester.pumpAndSettle();
    bridge.pending[0].complete(_data(from: 'OLD RANGE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NEW RANGE'), findsWidgets);
    expect(find.textContaining('OLD RANGE'), findsNothing);
  });

  testWidgets('Errors offer retry and recover without stale figures', (
    tester,
  ) async {
    final bridge = _Bridge()..fail = true;
    await show(tester, bridge);
    expect(find.text(strings['en']!.text('dashboardError')), findsOneWidget);
    expect(find.byType(DashboardChart), findsNothing);
    bridge.fail = false;
    final retry = find.text(strings['en']!.text('dashboardRetry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardDonut), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-balance')), findsOneWidget);
    expect(find.text(strings['en']!.text('dashboardError')), findsNothing);
  });

  testWidgets('Empty and future ranges explain missing actual data', (
    tester,
  ) async {
    final bridge = _Bridge()..response = _data(empty: true);
    await show(tester, bridge);
    expect(find.text(strings['en']!.text('dashboardEmpty')), findsOneWidget);
    bridge.response = _data(future: true);
    await selectRange(tester, 'yearly');
    expect(find.text(strings['en']!.text('dashboardFuture')), findsOneWidget);
    expect(find.byType(DashboardChart), findsNothing);
  });

  testWidgets(
    'Charts switch presentation, filter legends, and expose exact data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPouchTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardChart(
                title: 'Cash flow',
                hint: 'Recorded only',
                labels: const ['2024/01/15'],
                series: const [
                  DashboardSeries('Income', [12345]),
                  DashboardSeries('Expenses', [2345]),
                ],
                strings: strings['en']!,
                currency: 'CAD',
                switchable: true,
                interactiveLegend: true,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BarChart), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final group = chart.data.barGroups.first;
      final tooltip = chart.data.barTouchData.touchTooltipData.getTooltipItem(
        group,
        0,
        group.barRods.first,
        0,
      );
      expect(tooltip!.text, contains('123.45'));
      await tester.tap(find.text(strings['en']!.text('dashboardLines')));
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .length,
        1,
      );
      final dataToggle = find.text(strings['en']!.text('dashboardViewData'));
      await tester.ensureVisible(dataToggle);
      await tester.tap(dataToggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('123.45'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Single-value donut provides a keyboard-accessible amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(),
        home: Scaffold(
          body: DashboardDonut(
            title: 'Categories',
            hint: 'Recorded purchases',
            values: const [DashboardSlice('food', 12345)],
            currency: 'CAD',
            strings: strings['en']!,
          ),
        ),
      ),
    );
    final button = find.byType(TextButton);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('123.45'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
