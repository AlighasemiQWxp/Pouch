import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../core/pouch_theme.dart';
import 'pouch_coin.dart';

enum AppPage {
  today,
  insights,
  budget,
  planned,
  forecast,
  dashboard,
  reports,
  preferences,
  about,
}

String pageLabel(AppPage page) => switch (page) {
  AppPage.today => 'navToday',
  AppPage.insights => 'insightsTitle',
  AppPage.budget => 'navBudget',
  AppPage.planned => 'plansTitle',
  AppPage.forecast => 'forecastTitle',
  AppPage.dashboard => 'dashboardTitle',
  AppPage.reports => 'navReports',
  AppPage.preferences => 'navPreferences',
  AppPage.about => 'navAbout',
};
IconData pageIcon(AppPage page) => switch (page) {
  AppPage.today => Icons.space_dashboard_outlined,
  AppPage.insights => Icons.insights_outlined,
  AppPage.budget => Icons.account_balance_wallet_outlined,
  AppPage.planned => Icons.event_note_outlined,
  AppPage.forecast => Icons.insights_outlined,
  AppPage.dashboard => Icons.donut_large_rounded,
  AppPage.reports => Icons.bar_chart_outlined,
  AppPage.preferences => Icons.tune_outlined,
  AppPage.about => Icons.info_outline,
};

class PouchAppShell extends StatelessWidget {
  const PouchAppShell({
    required this.page,
    required this.strings,
    required this.onSelect,
    required this.onLanguage,
    required this.child,
    this.working = false,
    super.key,
  });
  final AppPage page;
  final AppStrings strings;
  final ValueChanged<AppPage> onSelect;
  final VoidCallback onLanguage;
  final Widget child;
  final bool working;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      final primary = [AppPage.today, AppPage.budget, AppPage.planned];
      final navigationPage = switch (page) {
        AppPage.about => AppPage.preferences,
        AppPage.dashboard ||
        AppPage.forecast ||
        AppPage.reports => AppPage.insights,
        _ => page,
      };
      final index = primary.indexOf(navigationPage);
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: desktop ? 64 : 76,
          leading: page == AppPage.about
              ? BackButton(onPressed: () => onSelect(AppPage.preferences))
              : null,
          title: desktop
              ? Text(
                  strings.text(pageLabel(navigationPage)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PouchCoin(size: 20),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Pouch',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      strings.text(pageLabel(navigationPage)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
          actions: [
            if (constraints.maxWidth >= 400)
              Tooltip(
                message: strings.text('local'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.offline_pin_outlined, size: 20),
                ),
              ),
            TextButton(
              onPressed: onLanguage,
              child: Text(strings.language == 'fa' ? 'EN' : 'فارسی'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            if (desktop)
              Material(
                color: context.pouchPalette.surface,
                child: Container(
                  width: 232,
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      end: BorderSide(color: context.pouchPalette.border),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            const PouchCoin(size: 36),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Pouch',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final item in [
                              AppPage.today,
                              AppPage.budget,
                              AppPage.planned,
                              AppPage.insights,
                              AppPage.preferences,
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  key: ValueKey('nav-${item.name}'),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  selected: navigationPage == item,
                                  selectedTileColor:
                                      context.pouchPalette.selection,
                                  leading: Icon(pageIcon(item)),
                                  title: Text(strings.text(pageLabel(item))),
                                  onTap: () => onSelect(item),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          strings.text('offlinePrivacyHint'),
                          style: TextStyle(
                            color: context.pouchPalette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    reverseDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.012),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(page), child: child),
                  ),
                  if (working)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: index < 0 ? primary.length : index,
                onDestinationSelected: (selected) {
                  if (selected < primary.length) {
                    onSelect(primary[selected]);
                  } else {
                    _more(context);
                  }
                },
                destinations: [
                  for (final item in primary)
                    NavigationDestination(
                      icon: Icon(pageIcon(item)),
                      label: strings.text(pageLabel(item)),
                    ),
                  NavigationDestination(
                    icon: const Icon(Icons.more_horiz),
                    label: strings.text('more'),
                  ),
                ],
              ),
      );
    },
  );
  void _more(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in [AppPage.insights, AppPage.preferences])
              ListTile(
                leading: Icon(pageIcon(item)),
                title: Text(strings.text(pageLabel(item))),
                selected:
                    page == item ||
                    (item == AppPage.insights &&
                        [
                          AppPage.dashboard,
                          AppPage.forecast,
                          AppPage.reports,
                        ].contains(page)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSelect(item);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
