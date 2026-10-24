import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pouch/core/pouch_bridge.dart';
import 'package:pouch/core/app_strings.dart';
import 'package:pouch/core/pouch_models.dart';
import 'package:pouch/core/pouch_theme.dart';
import 'package:pouch/widgets/pouch_period_selector.dart';

const active = PouchPeriod(
  'active',
  '2024-01-08',
  '2024-01-14',
  '2024-01-07',
  '2024-01-15',
  'weekly',
  0,
  'gregory',
  '2024-01-08',
  name: 'P-AB12CD34',
);
const past = PouchPeriod(
  'past',
  '2024-01-01',
  '2024-01-07',
  '2023-12-31',
  '2024-01-08',
  'weekly',
  0,
  'gregory',
  '2024-01-01',
  name: 'P-EF56AB78',
  status: 'closed',
);

class CalendarBridge extends PouchBridge {
  @override
  Future<(int, int, int)> dateParts(String date, String calendar) async =>
      (1402, 10, DateTime.parse(date).day + 10);
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
  for (final language in ['en', 'fa']) {
    for (final width in [320.0, 600.0]) {
      testWidgets(
        'Named period selector fits $language at $width with enlarged text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final strings = localizedStrings[language]!;
          var selected = active.id;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildPouchTheme(),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.6)),
                  child: Directionality(
                    textDirection: language == 'fa'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: StatefulBuilder(
                          builder: (context, setState) => PouchPeriodSelector(
                            bridge: CalendarBridge(),
                            calendar: language == 'fa' ? 'persian' : 'gregory',
                            periods: const [past, active],
                            selectedId: selected,
                            strings: strings,
                            onChanged: (id) => setState(() => selected = id),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(active.displayName), findsNothing);
          expect(find.text(strings.text('currentBudget')), findsOneWidget);
          expect(
            find.text(
              language == 'fa'
                  ? '۱۴۰۲ / ۱۰ / ۱۸ – ۱۴۰۲ / ۱۰ / ۲۴'
                  : 'Jan 8, 2024 – Jan 14, 2024',
            ),
            findsWidgets,
          );
          final field = tester.widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          );
          expect(field.initialValue, active.id);
          field.onChanged!(past.id);
          await tester.pumpAndSettle();
          expect(selected, past.id);
          expect(find.text(strings.text('otherBudget')), findsOneWidget);
          expect(find.text(past.displayName), findsNothing);
          expect(tester.takeException(), isNull);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
  testWidgets('Empty period selector cannot create an invalid assignment', (
    tester,
  ) async {
    var changed = false;
    final strings = AppStrings('en', {
      'budgetPeriod': 'Budget period',
      'choosePeriod': 'Choose a period',
      'choosePeriodHint': 'Create or select a budget period to continue.',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPouchTheme(),
        home: Scaffold(
          body: PouchPeriodSelector(
            bridge: CalendarBridge(),
            calendar: 'gregory',
            periods: const [],
            selectedId: null,
            strings: strings,
            onChanged: (_) => changed = true,
          ),
        ),
      ),
    );
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.onChanged, isNull);
    expect(changed, isFalse);
    expect(find.text(strings.text('choosePeriodHint')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
