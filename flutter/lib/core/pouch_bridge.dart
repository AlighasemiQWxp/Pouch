import 'dart:typed_data';
import 'dart:convert';

import 'package:pouch/src/rust/api.dart';
import 'package:pouch/src/rust/api.dart' as economic_api;

import 'pouch_models.dart';
import 'pouch_platform.dart';

typedef PouchMutation = Future<bool> Function(Future<PouchSnapshot> Function());

class PouchExpenseDraft {
  const PouchExpenseDraft(this.id, this.name, this.amount);

  final String id;
  final String name;
  final String amount;
}

class PouchBridge {
  PouchBridge({PouchPlatform? platform})
    : _platform = platform ?? PouchPlatform.create();

  final PouchPlatform _platform;
  late PouchApp _session;

  bool get isDesktop => _platform.isDesktop;
  Future<String> loadThemeStyle() => _platform.loadThemeStyle();
  Future<void> saveThemeStyle(String style) => _platform.saveThemeStyle(style);

  Future<PouchSnapshot> open() async {
    final bootstrap = await _platform.bootstrap();
    try {
      _session = await PouchApp.open(
        applicationDataDirectory: bootstrap.directory,
        legacyJsonCandidates: bootstrap.legacyJsonCandidates,
      );
      final raw = await _session.snapshot();
      await _platform.markDataImportComplete();
      return PouchSnapshot.fromBridge(raw);
    } catch (_) {
      await _platform.close();
      rethrow;
    }
  }

  Future<String> today() => _session.today();

  Future<(int year, int month, int day)> dateParts(
    String date,
    String calendar,
  ) async {
    final dynamic value = await _session.dateParts(
      date: date,
      calendar: calendar,
    );
    return (value.year as int, value.month as int, value.day as int);
  }

  Future<PouchCalendarMonth> calendarMonth(
    String date,
    String calendar,
    int monthOffset,
  ) async => PouchCalendarMonth.fromBridge(
    await _session.calendarMonth(
      date: date,
      calendar: calendar,
      monthOffset: monthOffset,
    ),
  );

  Future<String> calendarDate({
    required int year,
    required int month,
    required int day,
    required String calendar,
  }) => _session.calendarDate(
    year: year,
    month: month,
    day: day,
    calendar: calendar,
  );

  Future<PouchSnapshot> snapshot() async =>
      PouchSnapshot.fromBridge(await _session.snapshot());

  Future<PouchBudgetSummary> budgetSummary(String date) async =>
      PouchBudgetSummary.fromBridge(await _session.budgetSummary(date: date));

  Future<PouchSnapshot> updatePreferences({
    required String country,
    required String currency,
    required String language,
    required String calendar,
    required int weekStart,
  }) async => PouchSnapshot.fromBridge(
    await _session.updatePreferences(
      country: country,
      currency: currency,
      language: language,
      calendar: calendar,
      weekStart: weekStart,
    ),
  );

  Future<PouchSnapshot> addPurchase({
    required String id,
    required String date,
    required String description,
    required String amount,
    required String category,
  }) async => PouchSnapshot.fromBridge(
    await _session.addPurchase(
      id: id,
      date: date,
      description: description,
      amount: amount,
      category: category,
    ),
  );

  Future<PouchSnapshot> editPurchase({
    required String date,
    required String id,
    required String description,
    required String amount,
    required String category,
  }) async => PouchSnapshot.fromBridge(
    await _session.editPurchase(
      date: date,
      id: id,
      description: description,
      amount: amount,
      category: category,
    ),
  );

  Future<PouchSnapshot> removePurchase(String date, String id) async =>
      PouchSnapshot.fromBridge(
        await _session.removePurchase(date: date, id: id),
      );

  Future<PouchSnapshot> setDailyOverride(String date, String? amount) async =>
      PouchSnapshot.fromBridge(
        await _session.setDailyOverride(date: date, amount: amount),
      );

  Future<PouchSnapshot> recordIncome({
    required String id,
    required String date,
    required String amount,
  }) async => PouchSnapshot.fromBridge(
    await _session.recordIncome(id: id, date: date, amount: amount),
  );

  Future<PouchSnapshot> updateIncome({
    required String id,
    required String date,
    required String amount,
  }) async => PouchSnapshot.fromBridge(
    await _session.updateIncome(id: id, date: date, amount: amount),
  );

  Future<PouchSnapshot> scheduleIncome({
    required String id,
    required String date,
    required String amount,
  }) async => PouchSnapshot.fromBridge(
    await _session.scheduleIncome(id: id, date: date, amount: amount),
  );

  Future<PouchSnapshot> updateExpectedIncome({
    required String id,
    required String date,
    required String amount,
  }) async => PouchSnapshot.fromBridge(
    await _session.updateExpectedIncome(id: id, date: date, amount: amount),
  );

  Future<PouchSnapshot> markExpectedIncomeReceived({
    required String id,
    required String receivedDate,
  }) async => PouchSnapshot.fromBridge(
    await _session.markExpectedIncomeReceived(
      id: id,
      receivedDate: receivedDate,
    ),
  );

  Future<PouchSnapshot> removeExpectedIncome(String id) async =>
      PouchSnapshot.fromBridge(await _session.removeExpectedIncome(id: id));

  Future<PouchSnapshot> removeIncome(String id) async =>
      PouchSnapshot.fromBridge(await _session.removeIncome(id: id));

  Future<PouchSnapshot> removeBudgetPlan(String effective) async =>
      PouchSnapshot.fromBridge(
        await _session.removeBudgetPlan(effective: effective),
      );

  Future<PouchSnapshot> undoLastChange() async =>
      PouchSnapshot.fromBridge(await _session.undoLastChange());

  Future<PouchSnapshot> saveBudgetPlan({
    required String effective,
    required String? salary,
    required String dailyBudget,
    required List<PouchExpenseDraft> expenses,
    required String savings,
    required int payday,
  }) async => PouchSnapshot.fromBridge(
    await _session.saveBudgetPlan(
      effective: effective,
      salary: salary,
      dailyBudget: dailyBudget,
      expenseIds: expenses.map((value) => value.id).toList(growable: false),
      expenseNames: expenses.map((value) => value.name).toList(growable: false),
      expenseAmounts: expenses
          .map((value) => value.amount)
          .toList(growable: false),
      savings: savings,
      payday: payday,
    ),
  );

  Future<PouchSnapshot> savePlanned({
    required String id,
    required String description,
    required String amount,
    required String category,
    required String kind,
    required String date,
  }) async => PouchSnapshot.fromBridge(
    await _session.savePlanned(
      id: id,
      description: description,
      amount: amount,
      category: category,
      kind: kind,
      date: date,
    ),
  );

  Future<PouchSnapshot> removePlanned(String id) async =>
      PouchSnapshot.fromBridge(await _session.removePlanned(id: id));

  Future<PouchSnapshot> markPlannedPaid({
    required String planId,
    required String purchaseId,
    required String paidDate,
    required String amount,
  }) async => PouchSnapshot.fromBridge(
    await _session.markPlannedPaid(
      planId: planId,
      purchaseId: purchaseId,
      paidDate: paidDate,
      amount: amount,
    ),
  );

  Future<String> exportBackup() => _session.exportBackup();

  Future<String> exportRecoveryBackup() => _session.exportRecoveryBackup();

  Future<PouchSnapshot> importBackup(String contents) async =>
      PouchSnapshot.fromBridge(await _session.importBackup(contents: contents));

  Future<PouchSnapshot> reset() async =>
      PouchSnapshot.fromBridge(await _session.reset());

  Future<List<PouchGoalForecast>> goalForecast(String asOf) async {
    final values = await _session.goalForecast(asOf: asOf) as Iterable<dynamic>;
    return values.map(PouchGoalForecast.fromBridge).toList(growable: false);
  }

  final Map<String, Future<void>> _economicDownloads = {};

  Future<List<PouchEconomicCountry>> economicCountries() async {
    final values =
        jsonDecode(await economic_api.economicCountries()) as List<dynamic>;
    return values
        .map(
          (value) =>
              PouchEconomicCountry.fromJson(value as Map<String, dynamic>),
        )
        .toList();
  }

  Future<PouchStandardForecast> standardForecast(
    String asOf,
    String selectedId,
    String country,
  ) async => PouchStandardForecast.fromJson(
    jsonDecode(
      await _session.standardForecast(
        asOf: asOf,
        selectedId: selectedId,
        country: country,
      ),
    ) as Map<String, dynamic>,
  );

  Future<void> refreshEconomicProfile(String country, String currency) {
    final key = '$country:$currency';
    final pending = _economicDownloads[key];
    if (pending != null) return pending;
    final future = _downloadEconomicProfile(country, currency);
    _economicDownloads[key] = future;
    return future;
  }

  Future<void> _downloadEconomicProfile(String country, String currency) async {
    try {
      final contents = await economic_api.downloadEconomicProfile(
        country: country,
        currency: currency,
      );
      await _session.cacheEconomicProfile(contents: contents);
    } finally {
      _economicDownloads.remove('$country:$currency');
    }
  }

  Future<PouchSnapshot> customizeEconomicProfile({
    required String country,
    required String monthlyNetIncome,
    required String monthlyEssential,
    required String dailySpending,
    String? exchangeRate,
  }) async => PouchSnapshot.fromBridge(
    await _session.customizeEconomicProfile(
      country: country,
      monthlyNetIncome: monthlyNetIncome,
      monthlyEssential: monthlyEssential,
      dailySpending: dailySpending,
      exchangeRate: exchangeRate,
    ),
  );

  Future<PouchSnapshot> resetEconomicProfile(String country) async =>
      PouchSnapshot.fromBridge(
        await _session.resetEconomicProfile(country: country),
      );

  Future<PouchFinancialForecast> financialForecast(
    String asOf,
    String selectedId, {
    bool recommended = false,
    bool incomeRequired = false,
  }) async => PouchFinancialForecast.fromBridge(
    await _session.financialForecast(
      asOf: asOf,
      selectedId: selectedId,
      recommended: recommended,
      incomeRequired: incomeRequired,
    ),
  );

  Future<PouchReport> reportRange(String from, String through) async =>
      PouchReport.fromBridge(
        await _session.reportRange(from: from, through: through),
      );

  Future<PouchReport> reportWeek(String anchor, int weekStart) async =>
      PouchReport.fromBridge(
        await _session.reportWeek(anchor: anchor, weekStart: weekStart),
      );

  Future<PouchReport> reportMonth(String anchor, String calendar) async =>
      PouchReport.fromBridge(
        await _session.reportMonth(anchor: anchor, calendar: calendar),
      );

  Future<PouchReport> reportSpecific(List<String> days) async =>
      PouchReport.fromBridge(await _session.reportSpecific(days: days));

  Future<String?> pickBackup() => _platform.pickBackup();

  Future<bool> saveBackup(String filename, String contents) =>
      _platform.saveBackup(filename, contents);

  Future<void> printReport(String title, String html) =>
      _platform.printReport(title, html);

  Future<bool> printPdf(String title, Uint8List bytes) =>
      _platform.printPdf(title, bytes);

  Future<bool> savePdf(String filename, Uint8List bytes) =>
      _platform.savePdf(filename, bytes);

  Future<void> openExternalUrl(String url) => _platform.openExternalUrl(url);
}
