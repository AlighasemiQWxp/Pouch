class PouchPreferences {
  const PouchPreferences({
    required this.country,
    required this.currency,
    required this.language,
    required this.calendar,
    required this.weekStart,
  });

  final String country;
  final String currency;
  final String language;
  final String calendar;
  final int weekStart;

  factory PouchPreferences.fromBridge(dynamic value) => PouchPreferences(
    country: value.country as String,
    currency: value.currency as String,
    language: value.language as String,
    calendar: value.calendar as String,
    weekStart: value.weekStart as int,
  );
}

class PouchCalendarMonth {
  const PouchCalendarMonth({
    required this.startDate,
    required this.year,
    required this.month,
    required this.dayCount,
    required this.firstWeekday,
  });

  final String startDate;
  final int year;
  final int month;
  final int dayCount;
  final int firstWeekday;

  factory PouchCalendarMonth.fromBridge(dynamic value) => PouchCalendarMonth(
    startDate: value.startDate as String,
    year: value.year as int,
    month: value.month as int,
    dayCount: value.dayCount as int,
    firstWeekday: value.firstWeekday as int,
  );
}

class PouchIncome {
  const PouchIncome(this.id, this.date, this.amount);

  final String id;
  final String date;
  final int amount;

  factory PouchIncome.fromBridge(dynamic value) => PouchIncome(
    value.id as String,
    value.date as String,
    value.amount as int,
  );
}

class PouchExpectedIncome {
  const PouchExpectedIncome(this.id, this.date, this.amount);

  final String id;
  final String date;
  final int amount;

  factory PouchExpectedIncome.fromBridge(dynamic value) => PouchExpectedIncome(
    value.id as String,
    value.date as String,
    value.amount as int,
  );
}

class PouchRequiredExpense {
  const PouchRequiredExpense(this.id, this.name, this.amount);

  final String id;
  final String name;
  final int amount;

  factory PouchRequiredExpense.fromBridge(dynamic value) =>
      PouchRequiredExpense(
        value.id as String,
        value.name as String,
        value.amount as int,
      );
}

class PouchBudgetPlan {
  const PouchBudgetPlan({
    required this.effective,
    required this.salary,
    required this.dailyBudget,
    required this.expenses,
    required this.savings,
    required this.payday,
    required this.calendar,
    required this.legacy,
  });

  final String effective;
  final int? salary;
  final int dailyBudget;
  final List<PouchRequiredExpense> expenses;
  final int savings;
  final int payday;
  final String calendar;
  final bool legacy;

  factory PouchBudgetPlan.fromBridge(dynamic value) => PouchBudgetPlan(
    effective: value.effective as String,
    salary: value.salary as int?,
    dailyBudget: value.dailyBudget as int,
    expenses: List<dynamic>.from(value.expenses as Iterable)
        .map(PouchRequiredExpense.fromBridge)
        .toList(growable: false),
    savings: value.savings as int,
    payday: value.payday as int,
    calendar: value.calendar as String,
    legacy: value.legacy as bool,
  );
}

class PouchPurchase {
  const PouchPurchase({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.fundedByGoal,
  });

  final String id;
  final String description;
  final int amount;
  final String category;
  final bool fundedByGoal;

  factory PouchPurchase.fromBridge(dynamic value) => PouchPurchase(
    id: value.id as String,
    description: value.description as String,
    amount: value.amount as int,
    category: value.category as String,
    fundedByGoal: value.fundedByGoal as bool,
  );
}

class PouchDay {
  const PouchDay(this.date, this.budget, this.purchases);

  final String date;
  final int? budget;
  final List<PouchPurchase> purchases;

  factory PouchDay.fromBridge(dynamic value) => PouchDay(
    value.date as String,
    value.budget as int?,
    List<dynamic>.from(value.purchases as Iterable)
        .map(PouchPurchase.fromBridge)
        .toList(growable: false),
  );
}

class PouchPlannedItem {
  const PouchPlannedItem({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.kind,
    required this.date,
    required this.status,
    required this.paidDate,
    required this.purchaseId,
  });

  final String id;
  final String description;
  final int amount;
  final String category;
  final String kind;
  final String date;
  final String status;
  final String? paidDate;
  final String? purchaseId;

  factory PouchPlannedItem.fromBridge(dynamic value) => PouchPlannedItem(
    id: value.id as String,
    description: value.description as String,
    amount: value.amount as int,
    category: value.category as String,
    kind: value.kind as String,
    date: value.date as String,
    status: value.status as String,
    paidDate: value.paidDate as String?,
    purchaseId: value.purchaseId as String?,
  );
}

class PouchSnapshot {
  const PouchSnapshot({
    required this.revision,
    required this.recovered,
    required this.imported,
    required this.startDate,
    required this.preferences,
    required this.income,
    required this.expectedIncome,
    required this.plans,
    required this.days,
    required this.planned,
  });

  final int revision;
  final bool recovered;
  final bool imported;
  final String startDate;
  final PouchPreferences preferences;
  final List<PouchIncome> income;
  final List<PouchExpectedIncome> expectedIncome;
  final List<PouchBudgetPlan> plans;
  final List<PouchDay> days;
  final List<PouchPlannedItem> planned;

  factory PouchSnapshot.fromBridge(dynamic value) => PouchSnapshot(
    revision: value.revision as int,
    recovered: value.recovered as bool,
    imported: value.imported as bool,
    startDate: value.startDate as String,
    preferences: PouchPreferences.fromBridge(value.preferences),
    income: List<dynamic>.from(value.income as Iterable)
        .map(PouchIncome.fromBridge)
        .toList(growable: false),
    expectedIncome: List<dynamic>.from(value.expectedIncome as Iterable)
        .map(PouchExpectedIncome.fromBridge)
        .toList(growable: false),
    plans: List<dynamic>.from(value.plans as Iterable)
        .map(PouchBudgetPlan.fromBridge)
        .toList(growable: false),
    days: List<dynamic>.from(value.days as Iterable)
        .map(PouchDay.fromBridge)
        .toList(growable: false),
    planned: List<dynamic>.from(value.planned as Iterable)
        .map(PouchPlannedItem.fromBridge)
        .toList(growable: false),
  );

  PouchDay? day(String date) {
    for (final value in days) {
      if (value.date == date) return value;
    }
    return null;
  }

  PouchBudgetPlan planAt(String date) {
    var result = plans.first;
    for (final plan in plans) {
      if (plan.effective.compareTo(date) > 0) break;
      result = plan;
    }
    return result;
  }
}

class PouchBudgetSummary {
  const PouchBudgetSummary({
    required this.date,
    required this.periodEnd,
    required this.daysRemaining,
    required this.carry,
    required this.daily,
    required this.spent,
    required this.remaining,
    required this.income,
    required this.requiredExpenses,
    required this.savings,
    required this.funds,
    required this.reserved,
    required this.recommendation,
    required this.shortfall,
  });

  final String date;
  final String periodEnd;
  final int daysRemaining;
  final int carry;
  final int daily;
  final int spent;
  final int remaining;
  final int income;
  final int requiredExpenses;
  final int savings;
  final int funds;
  final int reserved;
  final int recommendation;
  final int shortfall;

  factory PouchBudgetSummary.fromBridge(dynamic value) => PouchBudgetSummary(
    date: value.date as String,
    periodEnd: value.periodEnd as String,
    daysRemaining: value.daysRemaining as int,
    carry: value.carry as int,
    daily: value.daily as int,
    spent: value.spent as int,
    remaining: value.remaining as int,
    income: value.income as int,
    requiredExpenses: value.requiredExpenses as int,
    savings: value.savings as int,
    funds: value.funds as int,
    reserved: value.reserved as int,
    recommendation: value.recommendation as int,
    shortfall: value.shortfall as int,
  );
}

class PouchGoalForecast {
  const PouchGoalForecast({
    required this.id,
    required this.periods,
    required this.requiredMonthly,
    required this.projected,
    required this.percent,
    required this.difference,
    required this.onTrack,
    required this.completionDays,
    required this.dailyReduction,
  });

  final String id;
  final int periods;
  final int? requiredMonthly;
  final int projected;
  final int percent;
  final int? difference;
  final bool onTrack;
  final int? completionDays;
  final int dailyReduction;

  factory PouchGoalForecast.fromBridge(dynamic value) => PouchGoalForecast(
    id: value.id as String,
    periods: value.periods as int,
    requiredMonthly: value.requiredMonthly as int?,
    projected: value.projected as int,
    percent: value.percent as int,
    difference: value.difference as int?,
    onTrack: value.onTrack as bool,
    completionDays: value.completionDays as int?,
    dailyReduction: value.dailyReduction as int,
  );
}

class PouchReportEntry {
  const PouchReportEntry({
    required this.date,
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.fundedByGoal,
  });

  final String date;
  final String id;
  final String description;
  final int amount;
  final String category;
  final bool fundedByGoal;

  factory PouchReportEntry.fromBridge(dynamic value) => PouchReportEntry(
    date: value.date as String,
    id: value.id as String,
    description: value.description as String,
    amount: value.amount as int,
    category: value.category as String,
    fundedByGoal: value.fundedByGoal as bool,
  );
}

class PouchDailyTotal {
  const PouchDailyTotal(this.date, this.amount);

  final String date;
  final int amount;

  factory PouchDailyTotal.fromBridge(dynamic value) =>
      PouchDailyTotal(value.date as String, value.amount as int);
}

class PouchCategoryTotal {
  const PouchCategoryTotal(this.category, this.amount);

  final String category;
  final int amount;

  factory PouchCategoryTotal.fromBridge(dynamic value) =>
      PouchCategoryTotal(value.category as String, value.amount as int);
}

class PouchPlannedReportEntry {
  const PouchPlannedReportEntry({
    required this.date,
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
  });

  final String date;
  final String id;
  final String description;
  final int amount;
  final String category;

  factory PouchPlannedReportEntry.fromBridge(dynamic value) =>
      PouchPlannedReportEntry(
        date: value.date as String,
        id: value.id as String,
        description: value.description as String,
        amount: value.amount as int,
        category: value.category as String,
      );
}

class PouchReport {
  const PouchReport({
    required this.dates,
    required this.entries,
    required this.daily,
    required this.categories,
    required this.planned,
    required this.total,
    required this.reserved,
  });

  final List<String> dates;
  final List<PouchReportEntry> entries;
  final List<PouchDailyTotal> daily;
  final List<PouchCategoryTotal> categories;
  final List<PouchPlannedReportEntry> planned;
  final int total;
  final int reserved;

  factory PouchReport.fromBridge(dynamic value) => PouchReport(
    dates: List<String>.from(value.dates as Iterable),
    entries: List<dynamic>.from(value.entries as Iterable)
        .map(PouchReportEntry.fromBridge)
        .toList(growable: false),
    daily: List<dynamic>.from(value.daily as Iterable)
        .map(PouchDailyTotal.fromBridge)
        .toList(growable: false),
    categories: List<dynamic>.from(value.categories as Iterable)
        .map(PouchCategoryTotal.fromBridge)
        .toList(growable: false),
    planned: List<dynamic>.from(value.planned as Iterable)
        .map(PouchPlannedReportEntry.fromBridge)
        .toList(growable: false),
    total: value.total as int,
    reserved: value.reserved as int,
  );
}
