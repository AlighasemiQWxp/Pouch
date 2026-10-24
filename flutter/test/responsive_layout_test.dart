import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pouch/core/app_strings.dart';
import 'package:pouch/core/pouch_theme.dart';
import 'package:pouch/widgets/pouch_app_shell.dart';
import 'package:pouch/widgets/pouch_widgets.dart';
import 'package:pouch/widgets/pouch_coin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final localizedStrings = <String, AppStrings>{};
  setUpAll(() async {
    for (final language in ['en', 'fa']) {
      localizedStrings[language] = await AppStrings.load(language);
    }
  });
  for (final language in ['en', 'fa']) {
    for (final width in [320.0, 600.0, 1280.0]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('Navigation and summaries fit $language $width at $scale', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final strings = localizedStrings[language]!;
          var selectedPage = AppPage.today;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildPouchTheme(),
              home: Builder(
                builder: (context) => Directionality(
                  textDirection: language == 'fa'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true,
                    ),
                    child: StatefulBuilder(
                      builder: (context, setState) => PouchAppShell(
                        page: selectedPage,
                        strings: strings,
                        onSelect: (page) => setState(() => selectedPage = page),
                        onLanguage: () {},
                        child: PouchPage(
                          children: [
                            PouchIntro(
                              eyebrow: strings.text('todayLabel'),
                              title: strings.text('todayTitle'),
                              description: strings.text('todayPageHint'),
                            ),
                            PouchSummaryRow(
                              label: strings.text('protectedSavings'),
                              value: '۱۲٬۵۰۰٬۰۰۰ تومان',
                            ),
                            PouchStatGrid(
                              children: [
                                PouchStat(
                                  label: strings.text('freeToSpend'),
                                  value: '۱۲٬۵۰۰٬۰۰۰ تومان',
                                  emphasized: true,
                                ),
                                PouchStat(
                                  label: strings.text('protectedSavings'),
                                  value: '20,000,000 CAD',
                                ),
                              ],
                            ),
                            PouchEmptyState(
                              title: strings.text('firstPeriodTitle'),
                              message: strings.text('firstPeriodHint'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(PouchCoin), findsOneWidget);
          expect(find.text('Pouch'), findsOneWidget);
          if (width >= 1000) {
            for (final page in [
              AppPage.today,
              AppPage.budget,
              AppPage.planned,
              AppPage.insights,
              AppPage.preferences,
            ]) {
              final tile = find.byKey(ValueKey('nav-${page.name}'));
              await tester.ensureVisible(tile);
              await tester.tap(tile);
              await tester.pumpAndSettle(
                const Duration(milliseconds: 100),
                EnginePhase.sendSemanticsUpdate,
                const Duration(seconds: 5),
              );
              expect(selectedPage, page);
              expect(tester.widget<ListTile>(tile).selected, isTrue);
              expect(
                tester
                    .widgetList<ListTile>(find.byType(ListTile))
                    .where((tile) => tile.selected),
                hasLength(1),
              );
              expect(tester.takeException(), isNull);
            }
          } else {
            await tester.tap(find.text(strings.text('more')));
            await tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );
            expect(find.text(strings.text('insightsTitle')), findsOneWidget);
            expect(find.text(strings.text('forecastTitle')), findsNothing);
            expect(find.text(strings.text('navPurchases')), findsNothing);
            expect(find.text(strings.text('navSavings')), findsNothing);
            expect(find.text(strings.text('navAbout')), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(strings.text('insightsTitle')));
            await tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );
            expect(selectedPage, AppPage.insights);
          }
          tester
              .widget<PouchAppShell>(find.byType(PouchAppShell))
              .onSelect(AppPage.about);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          expect(find.byType(BackButton), findsOneWidget);
          expect(find.byType(PouchCoin), findsOneWidget);
          expect(find.text('Pouch'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }, timeout: const Timeout(Duration(seconds: 30)));
      }
    }
  }
}
