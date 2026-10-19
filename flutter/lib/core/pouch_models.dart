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
  const PouchIncome(this.id, this.date, this.amount, {this.periodId});

  final String id;
  final String? periodId;
  final String date;
  final int amount;

  factory PouchIncome.fromBridge(dynamic value) => PouchIncome(
    value.id as String,
    value.date as String,
    value.amount as int,
    periodId: value.periodId as String?,
  );
}

class PouchExpectedIncome {
  const PouchExpectedIncome(this.id, this.date, this.amount, {this.periodId});

  final String id;
  final String? periodId;
  final String date;
  final int amount;

  factory PouchExpectedIncome.fromBridge(dynamic value) => PouchExpectedIncome(
    value.id as String,
    value.date as String,
    value.amount as int,
    periodId: value.periodId as String?,
  );
}

class PouchRequiredExpense {
  const PouchRequiredExpense(
    this.id,
    this.name,
    this.amount,
    this.date,
    this.recurrence,
    this.customDays,
    this.until,
  );
  final String id;
  final String name;
  final int amount;
  final String date;
  final String recurrence;
  final int customDays;
  final String? until;
  factory PouchRequiredExpense.fromBridge(dynamic value) =>
      PouchRequiredExpense(
        value.id as String,
        value.name as String,
        value.amount as int,
        value.date as String,
        value.recurrence as String,
        value.customDays as int,
        value.until as String?,
      );
}

class PouchBudgetPlan {
  const PouchBudgetPlan({
    required this.periodId,
    required this.effective,
    required this.savings,
  });
  final String periodId;
  final String effective;
  final int savings;
  factory PouchBudgetPlan.fromBridge(dynamic value) => PouchBudgetPlan(
    periodId: value.periodId as String,
    effective: value.effective as String,
    savings: value.savings as int,
  );
}

class PouchPeriod {
  const PouchPeriod(
    this.id,
    this.start,
    this.end,
    this.previousDate,
    this.nextDate,
    this.recurrence,
    this.customDays,
    this.calendar,
    this.changeFrom, {
    this.status = 'active',
    this.name = '',
    this.income = 0,
    this.expenses = 0,
    this.savings = 0,
    this.plannedSavings = 0,
    this.contributedSavings = 0,
    this.fundedExpenses = 0,
    this.remaining = 0,
    this.carry = 0,
    this.reserved = 0,
  });
  final String id;
  final String name;
  String get displayName => name.isEmpty ? id : name;
  final String start;
  final String end;
  final String previousDate;
  final String changeFrom;
  final String status;
  final int income,
      expenses,
      savings,
      plannedSavings,
      contributedSavings,
      fundedExpenses,
      remaining,
      carry,
      reserved;
  final String nextDate;
  final String recurrence;
  final int customDays;
  final String calendar;
  factory PouchPeriod.fromBridge(dynamic value) => PouchPeriod(
    value.id as String,
    value.start as String,
    value.end as String,
    value.previousDate as String,
    value.nextDate as String,
    value.recurrence as String,
    value.customDays as int,
    value.calendar as String,
    value.changeFrom as String,
    status: value.status as String,
    name: value.name as String,
    income: value.income as int,
    expenses: value.expenses as int,
    savings: value.savings as int,
    plannedSavings: value.plannedSavings as int,
    contributedSavings: value.contributedSavings as int,
    fundedExpenses: value.fundedExpenses as int,
    remaining: value.remaining as int,
    carry: value.carry as int,
    reserved: value.reserved as int,
  );
}

class PouchPeriodView {
  const PouchPeriodView(
    this.period,
    this.plan,
    this.budget,
    this.income,
    this.expectedIncome,
    this.expectedTotal,
    this.obligations, {
    this.targets = const [],
  });
  final PouchPeriod period;
  final PouchBudgetPlan plan;
  final PouchBudgetSummary budget;
  final List<PouchIncome> income;
  final List<PouchExpectedIncome> expectedIncome;
  final int expectedTotal;
  final List<PouchPlannedItem> obligations;
  final List<PouchPlannedItem> targets;
  factory PouchPeriodView.fromBridge(dynamic value) => PouchPeriodView(
    PouchPeriod.fromBridge(value.period),
    PouchBudgetPlan.fromBridge(value.plan),
    PouchBudgetSummary.fromBridge(value.budget),
    List<dynamic>.from(value.income as Iterable)
        .map(PouchIncome.fromBridge)
        .toList(growable: false),
    List<dynamic>.from(value.expectedIncome as Iterable)
        .map(PouchExpectedIncome.fromBridge)
        .toList(growable: false),
    value.expectedTotal as int,
    List<dynamic>.from(value.obligations as Iterable)
        .map(PouchPlannedItem.fromBridge)
        .toList(growable: false),
    targets: List<dynamic>.from(value.targets as Iterable)
        .map(PouchPlannedItem.fromBridge)
        .toList(growable: false),
  );
}

class PouchIncomeDay {
  const PouchIncomeDay(this.date, this.received, this.expected, this.count);
  final String date;
  final int received;
  final int expected;
  final int count;
  factory PouchIncomeDay.fromBridge(dynamic value) => PouchIncomeDay(
    value.date as String,
    value.received as int,
    value.expected as int,
    value.count as int,
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
  const PouchDay(this.date, this.purchases);

  final String date;
  final List<PouchPurchase> purchases;

  factory PouchDay.fromBridge(dynamic value) => PouchDay(
    value.date as String,
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
    this.essentialId,
    this.periodId,
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
  final String? essentialId;
  final String? periodId;

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
    essentialId: value.essentialId as String?,
    periodId: value.periodId as String?,
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
    required this.currentPlan,
    required this.currentPeriod,
    this.periods = const [],
    required this.essentials,
    required this.incomeDays,
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
  final PouchBudgetPlan currentPlan;
  final PouchPeriod? currentPeriod;
  final List<PouchPeriod> periods;
  final List<PouchRequiredExpense> essentials;
  final List<PouchIncomeDay> incomeDays;
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
    currentPlan: PouchBudgetPlan.fromBridge(value.currentPlan),
    currentPeriod: value.currentPeriod == null
        ? null
        : PouchPeriod.fromBridge(value.currentPeriod),
    periods: List<dynamic>.from(value.periods as Iterable)
        .map(PouchPeriod.fromBridge)
        .toList(growable: false),
    essentials: List<dynamic>.from(value.essentials as Iterable)
        .map(PouchRequiredExpense.fromBridge)
        .toList(growable: false),
    incomeDays: List<dynamic>.from(value.incomeDays as Iterable)
        .map(PouchIncomeDay.fromBridge)
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
    this.fundedExpenses = 0,
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
  final int fundedExpenses;
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
    fundedExpenses: value.fundedExpenses as int,
    recommendation: value.recommendation as int,
    shortfall: value.shortfall as int,
  );
}

class PouchFinancialForecast {
  const PouchFinancialForecast({
    required this.controllableSpending,
    required this.essentialExpenses,
    required this.configuredSavings,
    required this.extraDays,
    required this.fasterDays,
    required this.contribution,
    required this.periodIncome,
    required this.dailyAllowance,
    required this.requiredIncome,
    required this.dailyLimit,
    required this.periodSaving,
    required this.incomeGap,
    required this.spendingReduction,
    required this.allocated,
    required this.remaining,
    required this.completionDays,
    required this.completionDate,
    required this.onTrack,
    required this.overdue,
    required this.cycleDays,
  });

  final int controllableSpending;
  final int essentialExpenses;
  final int configuredSavings;
  final int? extraDays;
  final int? fasterDays;
  final int periodIncome;
  final int contribution;
  final int dailyAllowance;
  final int? requiredIncome;
  final int dailyLimit;
  final int? periodSaving;
  final int? incomeGap;
  final int spendingReduction;
  final int allocated;
  final int remaining;
  final int? completionDays;
  final String? completionDate;
  final bool onTrack;
  final bool overdue;
  final int cycleDays;

  factory PouchFinancialForecast.fromBridge(dynamic value) =>
      PouchFinancialForecast(
        controllableSpending: value.controllableSpending as int,
        essentialExpenses: value.essentialExpenses as int,
        configuredSavings: value.configuredSavings as int,
        extraDays: value.extraDays as int?,
        fasterDays: value.fasterDays as int?,
        contribution: value.contribution as int,
        periodIncome: value.periodIncome as int,
        dailyAllowance: value.dailyAllowance as int,
        requiredIncome: value.requiredIncome as int?,
        dailyLimit: value.dailyLimit as int,
        periodSaving: value.periodSaving as int?,
        incomeGap: value.incomeGap as int?,
        spendingReduction: value.spendingReduction as int,
        allocated: value.allocated as int,
        remaining: value.remaining as int,
        completionDays: value.completionDays as int?,
        completionDate: value.completionDate as String?,
        onTrack: value.onTrack as bool,
        overdue: value.overdue as bool,
        cycleDays: value.cycleDays as int,
      );
}

class PouchGoalForecast {
  const PouchGoalForecast({
    required this.id,
    required this.periods,
    required this.requiredPerPeriod,
    required this.projected,
    required this.percent,
    required this.difference,
    required this.onTrack,
    required this.completionDays,
    required this.dailyReduction,
  });

  final String id;
  final int periods;
  final int? requiredPerPeriod;
  final int projected;
  final int percent;
  final int? difference;
  final bool onTrack;
  final int? completionDays;
  final int dailyReduction;

  factory PouchGoalForecast.fromBridge(dynamic value) => PouchGoalForecast(
    id: value.id as String,
    periods: value.periods as int,
    requiredPerPeriod: value.requiredPerPeriod as int?,
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

class PouchEconomicCountry {
  const PouchEconomicCountry(
    this.code,
    this.labelKey,
    this.currency,
    this.automatic,
  );
  final String code;
  final String labelKey;
  final String currency;
  final bool automatic;
  factory PouchEconomicCountry.fromJson(Map<String, dynamic> value) =>
      PouchEconomicCountry(
        value['code'] as String,
        value['labelKey'] as String,
        value['currency'] as String,
        value['automatic'] as bool,
      );
}

class PouchEconomicObservation {
  const PouchEconomicObservation(
    this.indicator,
    this.value,
    this.unit,
    this.period,
    this.released,
  );
  final String indicator;
  final double value;
  final String unit;
  final String period;
  final String released;
  factory PouchEconomicObservation.fromJson(Map<String, dynamic> value) =>
      PouchEconomicObservation(
        value['indicator'] as String,
        (value['value'] as num).toDouble(),
        value['unit'] as String,
        value['period'] as String,
        value['released'] as String,
      );
}

class PouchStandardForecast {
  PouchStandardForecast.fromJson(Map<String, dynamic> value)
    : country = value['country'] as String,
      status = value['status'] as String,
      customized = value['customized'] as bool,
      needsRefresh = value['needsRefresh'] as bool,
      cacheWarning = value['cacheWarning'] as bool,
      downloaded = value['downloaded'] as String?,
      currency = value['currency'] as String,
      remaining = value['remaining'] as int,
      convertedRemaining = value['convertedRemaining'] as int?,
      convertedGoal = value['convertedGoal'] as int?,
      requiredMonthlySaving = value['requiredMonthlySaving'] as int?,
      requiredMonthlyIncome = value['requiredMonthlyIncome'] as int?,
      monthlyNetIncome = value['monthlyNetIncome'] as int?,
      monthlyEssential = value['monthlyEssential'] as int?,
      dailySpending = value['dailySpending'] as int?,
      monthlySaving = value['monthlySaving'] as int?,
      completionDays = value['completionDays'] as int?,
      completionDate = value['completionDate'] as String?,
      exchange = value['exchange'] as Map<String, dynamic>?,
      exchangeRateTrillionths = value['exchangeRateTrillionths'] as int?,
      observations = (value['observations'] as List<dynamic>)
          .map(
            (entry) => PouchEconomicObservation.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList();

  final String country;
  final String status;
  final bool customized;
  final bool needsRefresh;
  final bool cacheWarning;
  final String? downloaded;
  final String currency;
  final int remaining;
  final int? convertedRemaining;
  final int? convertedGoal;
  final int? requiredMonthlySaving;
  final int? requiredMonthlyIncome;
  final int? monthlyNetIncome;
  final int? monthlyEssential;
  final int? dailySpending;
  final int? monthlySaving;
  final int? completionDays;
  final String? completionDate;
  final Map<String, dynamic>? exchange;
  final int? exchangeRateTrillionths;
  final List<PouchEconomicObservation> observations;
}
