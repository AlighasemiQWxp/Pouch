import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/app_strings.dart';
import 'core/pouch_bridge.dart';
import 'core/pouch_models.dart';
import 'core/pouch_runtime.dart';
import 'core/pouch_theme.dart';
import 'features/about/about_screen.dart';
import 'features/budget_plan/budget_screen.dart';
import 'features/planned/planned_screen.dart';
import 'features/forecast/financial_forecast_screen.dart';
import 'features/preferences/preferences_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/today/today_screen.dart';
import 'widgets/pouch_app_shell.dart';
import 'widgets/pouch_motion.dart';
import 'widgets/pouch_period_selector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fa');
    await initializePouchCore();
    await _openApplication();
  } catch (error) {
    runApp(PouchStartupFailure(error: error.toString()));
  }
}

Future<void> _openApplication() async {
  try {
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
  late PouchSnapshot _snapshot = widget.initialSnapshot;
  late AppStrings _strings = widget.initialStrings;
  late String _today = widget.initialToday;
  late String _themeStyle = widget.initialThemeStyle;
  AppPage _page = AppPage.today;
  String? _selectedDay;
  String? _selectedPeriodId;
  bool _working = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _refreshToday());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_snapshot.imported) _showMessage('recordsImported');
      if (_snapshot.recovered) _showMessage('storageRecovered');
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
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
      final snapshot = await widget.bridge.snapshot();
      if (!mounted) return;
      setState(() {
        if (_selectedDay == _today) _selectedDay = null;
        _today = today;
        _snapshot = snapshot;
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
    if (message.contains('already starts')) return 'periodAlreadyStarts';
    if (message.contains('outside a period')) return 'periodContainsPlan';
    if (message.contains('non-overlapping') ||
        message.contains('planning horizon')) {
      return 'invalidPeriod';
    }
    if (message.contains('currency')) return 'currencyLocked';
    if (message.contains('amount')) return 'invalidAmount';
    if (message.contains('report')) return 'invalidReport';
    if (message.contains('newer app version') ||
        message.contains('storage format version') ||
        message.contains('development data format is incompatible')) {
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

  void _selectPage(AppPage page) {
    if (mounted) setState(() => _page = page);
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
    builder: (context, child) =>
        PouchMotion(child: child ?? const SizedBox.shrink()),
    home: PouchAppShell(
      page: _page,
      strings: _strings,
      working: _working,
      onSelect: _selectPage,
      onLanguage: () =>
          _setLanguage(_snapshot.preferences.language == 'en' ? 'fa' : 'en'),
      child: PouchPeriodScope(
        periodId: selectedPouchPeriod(_snapshot, _selectedPeriodId)?.id,
        onChanged: (id) => setState(() => _selectedPeriodId = id),
        child: _buildPage(),
      ),
    ),
  );

  Widget _buildPage() {
    switch (_page) {
      case AppPage.today:
        return TodayScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          working: _working,
          selectedDate: _selectedDay ?? _today,
          onDateChanged: (date) => setState(() => _selectedDay = date),
          undo: _undoLastChange,
          onOpenBudget: () => _selectPage(AppPage.budget),
          onOpenPlanned: () => _selectPage(AppPage.planned),
          run: _run,
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
      case AppPage.forecast:
        return FinancialForecastScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          run: _run,
          onOpenPlanned: () => _selectPage(AppPage.planned),
        );
      case AppPage.dashboard:
        return DashboardScreen(
          bridge: widget.bridge,
          snapshot: _snapshot,
          strings: _strings,
          today: _today,
          onOpenToday: () => _selectPage(AppPage.today),
          onOpenBudget: () => _selectPage(AppPage.budget),
          onOpenPlans: () => _selectPage(AppPage.planned),
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
          onOpenAbout: () => _selectPage(AppPage.about),
        );
      case AppPage.about:
        return AboutScreen(bridge: widget.bridge, strings: _strings);
    }
  }
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
                if (error.contains('development data format is incompatible'))
                  Builder(
                    builder: (context) => FilledButton(
                      onPressed: () => _reset(context),
                      child: const Text('Start a new budget / شروع بودجه جدید'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new budget / شروع بودجه جدید'),
        content: const Text(
          'Archive incompatible local data and start an empty budget? Original files will be kept in the app data folder.\nداده‌های ناسازگار بایگانی شوند و بودجه خالی آغاز شود؟ فایل‌های اصلی در پوشه داده‌های برنامه حفظ می‌شوند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel / انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset / بازنشانی'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PouchBridge().resetIncompatibleStorage();
      await _openApplication();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}
