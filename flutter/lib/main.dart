import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pouch/src/rust/frb_generated.dart';

import 'core/app_strings.dart';
import 'core/pouch_bridge.dart';
import 'core/pouch_models.dart';
import 'core/pouch_theme.dart';
import 'features/about/about_screen.dart';
import 'features/budget_plan/budget_screen.dart';
import 'features/planned/planned_screen.dart';
import 'features/preferences/preferences_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/today/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fa');
    await RustLib.init();
    final bridge = PouchBridge();
    final snapshot = await bridge.open();
    final today = await bridge.today();
    final themeStyle = await bridge.loadThemeStyle();
    final strings = await AppStrings.load(snapshot.preferences.language);
    runApp(
      PouchApplication(
        bridge: bridge,
        initialSnapshot: snapshot,
        initialStrings: strings,
        initialToday: today,
        initialThemeStyle: themeStyle,
      ),
    );
  } catch (error) {
    runApp(PouchStartupFailure(error: error.toString()));
  }
}

class PouchApplication extends StatefulWidget {
  const PouchApplication({
    required this.bridge,
    required this.initialSnapshot,
    required this.initialStrings,
    required this.initialToday,
    required this.initialThemeStyle,
    super.key,
  });

  final PouchBridge bridge;
  final PouchSnapshot initialSnapshot;
  final AppStrings initialStrings;
  final String initialToday;
  final String initialThemeStyle;

  @override
  State<PouchApplication> createState() => _PouchApplicationState();
}

class _PouchApplicationState extends State<PouchApplication>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late PouchSnapshot _snapshot = widget.initialSnapshot;
  late AppStrings _strings = widget.initialStrings;
  late String _today = widget.initialToday;
  late String _selectedDate = widget.initialToday;
  late String _themeStyle = widget.initialThemeStyle;
  AppPage _page = AppPage.today;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_snapshot.imported) _showMessage('recordsImported');
      if (_snapshot.recovered) _showMessage('storageRecovered');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshToday();
  }

  Future<void> _refreshToday() async {
    try {
      final today = await widget.bridge.today();
      if (!mounted || today == _today) return;
      setState(() {
        final wasFollowingToday = _selectedDate == _today;
        _today = today;
        if (wasFollowingToday) _selectedDate = today;
      });
    } catch (_) {}
  }

  Future<bool> _run(Future<PouchSnapshot> Function() operation) async {
    if (_working) return false;
    _messengerKey.currentState?.hideCurrentSnackBar();
    setState(() => _working = true);
    try {
      final next = await operation();
      if (!mounted) return false;
      final languageChanged =
          next.preferences.language != _snapshot.preferences.language;
      final calendarChanged =
          next.preferences.calendar != _snapshot.preferences.calendar;
      final strings = languageChanged
          ? await AppStrings.load(next.preferences.language)
          : _strings;
      if (!mounted) return false;
      setState(() {
        _snapshot = next;
        _strings = strings;
      });
      if (languageChanged &&
          calendarChanged &&
          next.preferences.language == 'fa') {
        _showMessage('calendarAutoChanged');
      }
      return true;
    } catch (error) {
      if (mounted) _showMessage(_errorKey(error));
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _undoLastChange() async {
    final undone = await _run(widget.bridge.undoLastChange);
    if (undone && mounted) _showMessage('undone');
  }

  String _errorKey(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('currency')) return 'currencyLocked';
    if (message.contains('amount')) return 'invalidAmount';
    if (message.contains('report')) return 'invalidReport';
    if (message.contains('newer app version') ||
        message.contains('storage format version')) {
      return 'unsupportedStorageVersion';
    }
    if (message.contains('recovery copy')) return 'noRecovery';
    if (message.contains('backup')) {
      if (message.contains('exceeds')) return 'backupTooLarge';
      return 'invalidData';
    }
    if (message.contains('date or calendar')) return 'invalidDate';
    if (message.contains('requested record')) return 'invalidEntry';
    if (message.contains('calculated total')) return 'totalTooLarge';
    if (message.contains('integrity') ||
        message.contains('could not be read or recovered')) {
      return 'storageUnreadable';
    }
    if (message.contains('storage')) return 'storageUnavailable';
    if (message.contains('invalid')) return 'invalidData';
    return 'saveFailed';
  }

  void _showMessage(String key) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_strings.text(key))));
  }

  Future<void> _setLanguage(String language) async {
    await _run(
      () => widget.bridge.updatePreferences(
        country: _snapshot.preferences.country,
        currency: _snapshot.preferences.currency,
        language: language,
        calendar: _snapshot.preferences.calendar,
        weekStart: _snapshot.preferences.weekStart,
      ),
    );
  }

  Future<void> _selectPage(AppPage page) async {
    _scaffoldKey.currentState?.closeDrawer();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _page = page);
  }

  Future<void> _setThemeStyle(String style) async {
    await widget.bridge.saveThemeStyle(style);
    if (!mounted) return;
    setState(() => _themeStyle = style);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pouch',
    theme: buildPouchTheme(_themeStyle),
    locale: Locale(_snapshot.preferences.language),
    supportedLocales: const [Locale('en'), Locale('fa')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    scaffoldMessengerKey: _messengerKey,
    home: Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          _buildPage(),
          if (_working)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    ),
  );

  PreferredSizeWidget _buildAppBar() {
    final palette = PouchPalette.forStyle(_themeStyle);
    return AppBar(
      toolbarHeight: 76,
      leadingWidth: 60,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: _strings.text('menu'),
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
      ),
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/pouch-icon.png', width: 38, height: 38),
          ),
          const SizedBox(width: 10),
          const Text(
            'Pouch',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          _PouchCoin(color: palette.goldBright),
        ],
      ),
      actions: _buildAppBarActions(),
    );
  }

  List<Widget> _buildAppBarActions() {
    final palette = PouchPalette.forStyle(_themeStyle);
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      return [
        TextButton(
          onPressed: () => _setLanguage(
            _snapshot.preferences.language == 'en' ? 'fa' : 'en',
          ),
          style: TextButton.styleFrom(
            foregroundColor: palette.goldDeep,
            minimumSize: const Size(48, 40),
          ),
          child: Text(
            _snapshot.preferences.language == 'en' ? 'فا' : 'EN',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (width >= 400)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Tooltip(
              message: _strings.text('local'),
              child: Icon(
                Icons.offline_pin_rounded,
                color: palette.goldBright,
                size: 21,
              ),
            ),
          ),
      ];
    }
    return [
      Container(
        margin: const EdgeInsetsDirectional.only(end: 8),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _languageButton('en', 'English', palette),
            _languageButton('fa', 'فارسی', palette),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Tooltip(
          message: _strings.text('local'),
          child: Icon(
            Icons.offline_pin_rounded,
            color: palette.goldBright,
            size: 21,
          ),
        ),
      ),
    ];
  }

  Widget _languageButton(String language, String label, PouchPalette palette) =>
      TextButton(
        onPressed: _snapshot.preferences.language == language
            ? null
            : () => _setLanguage(language),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          foregroundColor: _snapshot.preferences.language == language
              ? Colors.white
              : palette.muted,
          backgroundColor: _snapshot.preferences.language == language
              ? palette.goldDeep
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );

  Widget _buildDrawer() {
    final palette = PouchPalette.forStyle(_themeStyle);
    return Drawer(
      width: 340,
      backgroundColor: palette.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.asset(
                      'assets/pouch-icon.png',
                      width: 42,
                      height: 42,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Pouch',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _strings.text('closeMenu'),
                    onPressed: () => _scaffoldKey.currentState?.closeDrawer(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 18, 10),
              child: Text(
                _strings.text('drawerLabel').toUpperCase(),
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            for (final page in AppPage.values)
              ListTile(
                selected: page == _page,
                selectedTileColor: palette.selection,
                leading: Icon(
                  _pageIcon(page),
                  color: page == _page ? palette.gold : palette.muted,
                ),
                title: Text(_pageTitle(page)),
                onTap: () => _selectPage(page),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                minVerticalPadding: 12,
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Text(
                _strings.text('drawerHint'),
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case AppPage.today:
        return TodayScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          selectedDate: _selectedDate,
          working: _working,
          onDateChanged: (date) => setState(() => _selectedDate = date),
          run: _run,
          undo: _undoLastChange,
        );
      case AppPage.planned:
        return PlannedScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          run: _run,
          undo: _undoLastChange,
        );
      case AppPage.reports:
        return ReportsScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
        );
      case AppPage.budget:
        return BudgetScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          run: _run,
          undo: _undoLastChange,
        );
      case AppPage.preferences:
        return PreferencesScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          run: _run,
          themeStyle: _themeStyle,
          onThemeStyleChanged: _setThemeStyle,
        );
      case AppPage.about:
        return AboutScreen(bridge: widget.bridge, strings: _strings);
    }
  }

  String _pageTitle(AppPage page) {
    return _strings.text(switch (page) {
      AppPage.today => 'navToday',
      AppPage.planned => 'navPlanned',
      AppPage.reports => 'navReports',
      AppPage.budget => 'navBudget',
      AppPage.preferences => 'navPreferences',
      AppPage.about => 'navAbout',
    });
  }

  IconData _pageIcon(AppPage page) {
    return switch (page) {
      AppPage.today => Icons.today_rounded,
      AppPage.planned => Icons.event_note_rounded,
      AppPage.reports => Icons.insights_rounded,
      AppPage.budget => Icons.account_balance_wallet_rounded,
      AppPage.preferences => Icons.tune_rounded,
      AppPage.about => Icons.info_outline_rounded,
    };
  }
}

enum AppPage { today, planned, reports, budget, preferences, about }

class _PouchCoin extends StatefulWidget {
  const _PouchCoin({required this.color});

  final Color color;

  @override
  State<_PouchCoin> createState() => _PouchCoinState();
}

class _PouchCoinState extends State<_PouchCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _rotation,
    builder: (context, _) {
      final angle = _rotation.value * 2 * math.pi;
      final front = _rotation.value < 0.5;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY(angle),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF8B4513), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xCC8B4513),
                spreadRadius: 1.5,
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color,
                const Color(0xFFE49A25),
                const Color(0xFFFFC94D),
              ],
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFF0BA), width: 1),
            ),
            child: Icon(
              front ? Icons.attach_money_rounded : Icons.savings_outlined,
              size: 15,
              color: const Color(0xFF75400D),
            ),
          ),
        ),
      );
    },
  );
}

class PouchStartupFailure extends StatelessWidget {
  const PouchStartupFailure({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildPouchTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/pouch-icon.png', width: 76, height: 76),
                const SizedBox(height: 18),
                const Text(
                  'Pouch',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Saved data could not be opened.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PouchPalette.forStyle('classic').muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
