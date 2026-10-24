class DashboardSelection {
  const DashboardSelection({
    this.mode = 'monthly',
    required this.anchor,
    this.from,
    this.through,
    this.periodId,
  });

  final String mode;
  final String anchor;
  final String? from;
  final String? through;
  final String? periodId;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'anchor': anchor,
    'from': from,
    'through': through,
    'periodId': periodId,
  };

  DashboardSelection copyWith({
    String? mode,
    String? anchor,
    String? from,
    String? through,
    String? periodId,
  }) => DashboardSelection(
    mode: mode ?? this.mode,
    anchor: anchor ?? this.anchor,
    from: from ?? this.from,
    through: through ?? this.through,
    periodId: periodId ?? this.periodId,
  );
}

class DashboardSlice {
  const DashboardSlice(this.key, this.amount);
  final String key;
  final int amount;
  factory DashboardSlice.fromJson(Map<String, dynamic> json) =>
      DashboardSlice(json['key'] as String, json['amount'] as int);
}

class DashboardPoint {
  DashboardPoint.fromJson(Map<String, dynamic> json)
    : label = json['label'] as String,
      endLabel = json['endLabel'] as String,
      income = json['income'] as int,
      expenses = json['expenses'] as int,
      contributions = json['contributions'] as int,
      releases = json['releases'] as int,
      cash = json['cash'] as int,
      savings = json['savings'] as int;

  final String label, endLabel;
  final int income, expenses, contributions, releases, cash, savings;
  String get rangeLabel {
    if (label == endLabel) return label;
    return '$label – $endLabel';
  }
}

class DashboardProgressValue {
  const DashboardProgressValue({
    required this.key,
    required this.name,
    required this.amount,
    required this.target,
    required this.basisPoints,
  });

  factory DashboardProgressValue.fromJson(Map<String, dynamic> json) =>
      DashboardProgressValue(
        key: json['key'] as String,
        name: json['name'] as String,
        amount: json['amount'] as int,
        target: json['target'] as int,
        basisPoints: json['basisPoints'] as int,
      );

  final String key, name;
  final int amount, target, basisPoints;
}

class DashboardComparison {
  DashboardComparison.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      from = json['from'] as String,
      through = json['through'] as String,
      income = json['income'] as int,
      expenses = json['expenses'] as int,
      planned = json['planned'] as int,
      paid = json['paid'] as int,
      savingsTarget = json['savingsTarget'] as int,
      savings = json['savings'] as int;

  final String name, from, through;
  final int income, expenses, planned, paid, savingsTarget, savings;
  String get rangeLabel => '$name\n$from – $through';
}

class DashboardData {
  DashboardData.fromJson(Map<String, dynamic> json)
    : fromLabel = json['fromLabel'] as String,
      throughLabel = json['throughLabel'] as String,
      asOfLabel = json['asOfLabel'] as String,
      income = json['income'] as int,
      assignedIncome = json['assignedIncome'] as int?,
      expenses = json['expenses'] as int,
      net = json['net'] as int,
      cash = json['cash'] as int,
      free = json['free'] as int,
      protectedSavings = json['protectedSavings'] as int,
      reserved = json['reserved'] as int,
      contributions = json['contributions'] as int,
      releases = json['releases'] as int,
      hasActivity = json['hasActivity'] as bool,
      futureOnly = json['futureOnly'] as bool,
      goalCount = json['goalCount'] as int,
      comparisonCount = json['comparisonCount'] as int,
      categories = _items(json['categories'], DashboardSlice.fromJson),
      spending = _items(json['spending'], DashboardSlice.fromJson),
      allocation = _items(json['allocation'], DashboardSlice.fromJson),
      points = _items(json['points'], DashboardPoint.fromJson),
      progress = _items(json['progress'], DashboardProgressValue.fromJson),
      goals = _items(json['goals'], DashboardProgressValue.fromJson),
      comparisons = _items(json['comparisons'], DashboardComparison.fromJson);

  final String fromLabel, throughLabel, asOfLabel;
  final int income, expenses, net, cash, free, protectedSavings, reserved;
  final int contributions, releases, goalCount, comparisonCount;
  final int? assignedIncome;
  final bool hasActivity, futureOnly;
  final List<DashboardSlice> categories, spending, allocation;
  final List<DashboardPoint> points;
  final List<DashboardProgressValue> progress, goals;
  final List<DashboardComparison> comparisons;

  static List<T> _items<T>(
    Object? value,
    T Function(Map<String, dynamic>) parse,
  ) => (value as List<dynamic>)
      .map((item) => parse(item as Map<String, dynamic>))
      .toList(growable: false);
}
