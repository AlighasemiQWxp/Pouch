import 'package:flutter/services.dart';
import 'package:pouch/src/rust/frb_generated.dart';

import 'pouch_models.dart';

typedef PouchMutation = Future<bool> Function(Future<PouchSnapshot> Function());

class PouchExpenseDraft {
  const PouchExpenseDraft(this.id, this.name, this.amount);

  final String id;
  final String name;
  final String amount;
}

class PouchBridge {
  static const MethodChannel _native = MethodChannel('com.daybook.app/legacy');

  dynamic _session;

  Future<String> loadThemeStyle() async {
    try {
      final value = await _native.invokeMethod<String>('getThemeStyle');
      if (value == 'ocean' || value == 'forest') return value!;
    } catch (_) {}
    return 'classic';
  }

  Future<void> saveThemeStyle(String style) async {
    await _native.invokeMethod<void>(
      'setThemeStyle',
      <String, Object>{'style': style},
    );
  }

  Future<PouchSnapshot> open() async {
    final bootstrap = await _native.invokeMapMethod<String, Object?>(
      'getBootstrapData',
    );
    if (bootstrap == null)
      throw StateError('Pouch could not read its Android storage location.');
    final dataDirectory = bootstrap['dataDirectory'] as String?;
    if (dataDirectory == null || dataDirectory.isEmpty) {
      throw StateError('Pouch could not read its Android storage location.');
    }

    final dynamic api = RustLib.instance.api;
    final legacyJsonCandidates =
        [
              bootstrap['legacyPrimary'],
              bootstrap['legacyRecovery'],
              bootstrap['legacyOriginal'],
            ]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false);
    _session = await api.crateApiPouchAppOpen(
      applicationDataDirectory: dataDirectory,
      legacyJsonCandidates: legacyJsonCandidates,
    );
    final raw = await _session.snapshot();
    await _native.invokeMethod<void>('markDataImportComplete');
    return PouchSnapshot.fromBridge(raw);
  }

  Future<String> today() async => await _session.today() as String;

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
  }) async => await _session.calendarDate(
    year: year,
    month: month,
    day: day,
    calendar: calendar,
  ) as String;

  Future<PouchSnapshot> snapshot() async =>
      PouchSnapshot.fromBridge(await _session.snapshot());

  Future<PouchBudgetSummary> budgetSummary(String date) async =>
      PouchBudgetSummary.fromBridge(await _session.budgetSummary(date: date));

  Future<PouchSnapshot> updatePreferences({
    required String currency,
    required String language,
    required String calendar,
    required int weekStart,
  }) async => PouchSnapshot.fromBridge(
    await _session.updatePreferences(
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

  Future<String> exportBackup() async =>
      await _session.exportBackup() as String;

  Future<String> exportRecoveryBackup() async =>
      await _session.exportRecoveryBackup() as String;

  Future<PouchSnapshot> importBackup(String contents) async =>
      PouchSnapshot.fromBridge(await _session.importBackup(contents: contents));

  Future<PouchSnapshot> reset() async =>
      PouchSnapshot.fromBridge(await _session.reset());

  Future<List<PouchGoalForecast>> goalForecast(String asOf) async {
    final values = await _session.goalForecast(asOf: asOf) as Iterable<dynamic>;
    return values.map(PouchGoalForecast.fromBridge).toList(growable: false);
  }

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

  Future<String?> pickBackup() => _native.invokeMethod<String>('pickBackup');

  Future<bool> saveBackup(String filename, String contents) async =>
      await _native.invokeMethod<bool>('saveBackup', {
        'filename': filename,
        'contents': contents,
      }) ??
      false;

  Future<void> printReport(String title, String html) =>
      _native.invokeMethod<void>('printReport', {'title': title, 'html': html});

  Future<void> openExternalUrl(String url) =>
      _native.invokeMethod<void>('openExternalUrl', {'url': url});
}
