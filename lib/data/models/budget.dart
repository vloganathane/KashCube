/// Budget model — stores a per-category monthly spending limit.
///
/// `spentAmount` is computed at query time from the transactions table and is
/// never persisted; the DB column is kept for caching but we always re-compute.
class Budget {
  final int? id;
  final int year;
  final int month;
  final String category;
  final double budgetAmount;

  /// Dynamically computed from transactions at load time.
  final double spentAmount;

  /// Alert threshold as a percentage (e.g. 80 → alert at 80%).
  final int alertAtPercentage;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Budget({
    this.id,
    required this.year,
    required this.month,
    required this.category,
    required this.budgetAmount,
    this.spentAmount = 0,
    this.alertAtPercentage = 80,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  // ---------------------------------------------------------------------------
  // Computed properties
  // ---------------------------------------------------------------------------

  double get remainingAmount => budgetAmount - spentAmount;
  double get spentPercentage =>
      budgetAmount > 0 ? (spentAmount / budgetAmount).clamp(0.0, 1.0) : 0;
  bool get isOverBudget => spentAmount > budgetAmount;
  bool get isNearLimit =>
      !isOverBudget && spentPercentage >= alertAtPercentage / 100;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Only includes columns that exist in the DB schema.
  /// `spentAmount`, `remainingAmount`, `isActive`, `updatedAt` are computed or
  /// from the old schema and must NOT be persisted.
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'year': year,
        'month': month,
        'category': category,
        'budget_amount': budgetAmount,
        'alert_at_percentage': alertAtPercentage,
        'created_at': createdAt.toIso8601String(),
      };

  factory Budget.fromMap(Map<String, dynamic> m) => Budget(
        id: m['id'] as int?,
        year: m['year'] as int,
        month: m['month'] as int,
        category: m['category'] as String,
        budgetAmount: (m['budget_amount'] as num).toDouble(),
        spentAmount: (m['spent_amount'] as num? ?? 0).toDouble(),
        alertAtPercentage: (m['alert_at_percentage'] as int? ?? 80),
        isActive: (m['is_active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)
            : null,
      );

  Budget copyWith({
    int? id,
    int? year,
    int? month,
    String? category,
    double? budgetAmount,
    double? spentAmount,
    int? alertAtPercentage,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Budget(
        id: id ?? this.id,
        year: year ?? this.year,
        month: month ?? this.month,
        category: category ?? this.category,
        budgetAmount: budgetAmount ?? this.budgetAmount,
        spentAmount: spentAmount ?? this.spentAmount,
        alertAtPercentage: alertAtPercentage ?? this.alertAtPercentage,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
