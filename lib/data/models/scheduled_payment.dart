import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// ScheduledFrequency
// ---------------------------------------------------------------------------

/// How often a [ScheduledPayment] recurs.
enum ScheduledFrequency {
  daily,
  weekly,
  biweekly,
  monthly,
  quarterly,
  yearly;

  String get label => switch (this) {
        ScheduledFrequency.daily => 'Daily',
        ScheduledFrequency.weekly => 'Weekly',
        ScheduledFrequency.biweekly => 'Bi-weekly',
        ScheduledFrequency.monthly => 'Monthly',
        ScheduledFrequency.quarterly => 'Quarterly',
        ScheduledFrequency.yearly => 'Yearly',
      };

  String get dbValue => name;

  static ScheduledFrequency fromDb(String value) =>
      ScheduledFrequency.values.firstWhere(
        (f) => f.name == value,
        orElse: () => ScheduledFrequency.monthly,
      );

  /// Next occurrence after [from].
  DateTime nextOccurrence(DateTime from) => switch (this) {
        ScheduledFrequency.daily => from.add(const Duration(days: 1)),
        ScheduledFrequency.weekly => from.add(const Duration(days: 7)),
        ScheduledFrequency.biweekly => from.add(const Duration(days: 14)),
        ScheduledFrequency.monthly =>
          DateTime(from.year, from.month + 1, from.day),
        ScheduledFrequency.quarterly =>
          DateTime(from.year, from.month + 3, from.day),
        ScheduledFrequency.yearly =>
          DateTime(from.year + 1, from.month, from.day),
      };

  /// Normalise [amount] to a monthly equivalent for budget summaries.
  double toMonthly(double amount) => switch (this) {
        ScheduledFrequency.daily => amount * 30,
        ScheduledFrequency.weekly => amount * 4,
        ScheduledFrequency.biweekly => amount * 2,
        ScheduledFrequency.monthly => amount,
        ScheduledFrequency.quarterly => amount / 3,
        ScheduledFrequency.yearly => amount / 12,
      };
}

// ---------------------------------------------------------------------------
// ScheduledPayment
// ---------------------------------------------------------------------------

/// Unified scheduled payment — replaces both the legacy `Bill` and
/// `RecurringTransaction` models.
///
/// Three operating modes:
/// * **Recurring reminder** (`isOneTime=false, autoCreate=false`) — e.g. rent,
///   electricity. App reminds you; you mark it paid manually.
/// * **Recurring auto** (`isOneTime=false, autoCreate=true`) — e.g. salary,
///   SIP. App auto-creates a real transaction in the ledger on each due date.
/// * **One-time** (`isOneTime=true`) — single upcoming payment/receipt.
///   Optionally auto-creates a transaction on the due date.
class ScheduledPayment extends Equatable {
  const ScheduledPayment({
    this.id,
    required this.name,
    required this.amount,
    required this.type,
    required this.category,
    required this.nextDate,
    this.isOneTime = false,
    this.frequency,
    this.dueDay,
    this.autoCreate = false,
    this.isAutoPay = false,
    this.isActive = true,
    this.lastPaidDate,
    this.lastGenerated,
    this.partyName,
    this.partyId,
    this.paymentMethod,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.billContext = 'personal',
  });

  final int? id;

  /// Human-readable label: "Netflix", "Electricity", "Salary".
  final String name;
  final double amount;

  /// `'income'` or `'expense'`.
  final String type;
  final String category;

  /// `true` → single upcoming event; `false` → repeating schedule.
  final bool isOneTime;

  /// Recurrence pattern. `null` when [isOneTime] is `true`.
  final ScheduledFrequency? frequency;

  /// Day-of-month (1–28) for monthly frequency; unused for other frequencies.
  final int? dueDay;

  /// When `true` a real transaction is auto-created on the due date.
  final bool autoCreate;

  /// Decorative: standing instruction / mandate already set up with bank.
  final bool isAutoPay;

  final bool isActive;

  /// Context for routing: `'personal'` (Transactions tab) or
  /// `'business'` (Business tab → Payables).
  final String billContext;

  /// Stored next due date — updated after each payment or auto-generation.
  final DateTime nextDate;

  /// When the user last manually marked this paid.
  final DateTime? lastPaidDate;

  /// When the last auto-created transaction was generated.
  final DateTime? lastGenerated;

  final String? partyName;

  /// Party FK — links this payment to a Party record for Party 360° aggregation.
  final int? partyId;

  final String? paymentMethod;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  // ── Computed ─────────────────────────────────────────────────────────────

  bool get isIncome => type == 'income';

  /// Whether this payment has been settled for the current billing period.
  bool get isPaidThisPeriod {
    if (isOneTime) return lastPaidDate != null;
    if (lastPaidDate == null) return false;
    final now = DateTime.now();
    final paid = lastPaidDate!;
    return switch (frequency ?? ScheduledFrequency.monthly) {
      ScheduledFrequency.daily => paid.year == now.year &&
          paid.month == now.month &&
          paid.day == now.day,
      ScheduledFrequency.weekly => now.difference(paid).inDays < 7,
      ScheduledFrequency.biweekly => now.difference(paid).inDays < 14,
      ScheduledFrequency.monthly =>
        paid.year == now.year && paid.month == now.month,
      ScheduledFrequency.quarterly => () {
          final paidQ = (paid.month - 1) ~/ 3;
          final nowQ = (now.month - 1) ~/ 3;
          return paid.year == now.year && paidQ == nowQ;
        }(),
      ScheduledFrequency.yearly => paid.year == now.year,
    };
  }

  bool get isOverdue {
    if (!isActive || isPaidThisPeriod) return false;
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return DateTime(nextDate.year, nextDate.month, nextDate.day)
        .isBefore(today);
  }

  /// Days until next due date. Negative = overdue.
  int get daysUntilDue {
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final due = DateTime(nextDate.year, nextDate.month, nextDate.day);
    return due.difference(today).inDays;
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'amount': amount,
        'type': type,
        'category': category,
        'is_one_time': isOneTime ? 1 : 0,
        'frequency': frequency?.dbValue,
        'due_day': dueDay,
        'auto_create': autoCreate ? 1 : 0,
        'is_auto_pay': isAutoPay ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'next_date': nextDate.toIso8601String(),
        'last_paid_date': lastPaidDate?.toIso8601String(),
        'last_generated': lastGenerated?.toIso8601String(),
        'party_name': partyName,
        if (partyId != null) 'party_id': partyId,
        'payment_method': paymentMethod,
        'notes': notes,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'bill_context': billContext,
      };

  factory ScheduledPayment.fromMap(Map<String, dynamic> map) =>
      ScheduledPayment(
        id: map['id'] as int?,
        name: map['name'] as String,
        amount: (map['amount'] as num).toDouble(),
        type: map['type'] as String? ?? 'expense',
        category: map['category'] as String,
        isOneTime: (map['is_one_time'] as int?) == 1,
        frequency: map['frequency'] != null
            ? ScheduledFrequency.fromDb(map['frequency'] as String)
            : null,
        dueDay: map['due_day'] as int?,
        autoCreate: (map['auto_create'] as int?) == 1,
        isAutoPay: (map['is_auto_pay'] as int?) == 1,
        isActive: (map['is_active'] as int?) != 0,
        nextDate: DateTime.parse(map['next_date'] as String),
        lastPaidDate: map['last_paid_date'] != null
            ? DateTime.parse(map['last_paid_date'] as String)
            : null,
        lastGenerated: map['last_generated'] != null
            ? DateTime.parse(map['last_generated'] as String)
            : null,
        partyName: map['party_name'] as String?,
        partyId: map['party_id'] as int?,
        paymentMethod: map['payment_method'] as String?,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : DateTime.now(),
        updatedAt: map['updated_at'] != null
            ? DateTime.parse(map['updated_at'] as String)
            : null,
        deletedAt: map['deleted_at'] != null
            ? DateTime.parse(map['deleted_at'] as String)
            : null,
        billContext: map['bill_context'] as String? ?? 'personal',
      );

  ScheduledPayment copyWith({
    int? id,
    String? name,
    double? amount,
    String? type,
    String? category,
    bool? isOneTime,
    ScheduledFrequency? frequency,
    int? dueDay,
    bool? autoCreate,
    bool? isAutoPay,
    bool? isActive,
    DateTime? nextDate,
    DateTime? lastPaidDate,
    DateTime? lastGenerated,
    String? partyName,
    int? partyId,
    String? paymentMethod,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? billContext,
  }) =>
      ScheduledPayment(
        id: id ?? this.id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        category: category ?? this.category,
        isOneTime: isOneTime ?? this.isOneTime,
        frequency: frequency ?? this.frequency,
        dueDay: dueDay ?? this.dueDay,
        autoCreate: autoCreate ?? this.autoCreate,
        isAutoPay: isAutoPay ?? this.isAutoPay,
        isActive: isActive ?? this.isActive,
        nextDate: nextDate ?? this.nextDate,
        lastPaidDate: lastPaidDate ?? this.lastPaidDate,
        lastGenerated: lastGenerated ?? this.lastGenerated,
        partyName: partyName ?? this.partyName,
        partyId: partyId ?? this.partyId,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        billContext: billContext ?? this.billContext,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        amount,
        type,
        category,
        isOneTime,
        frequency,
        dueDay,
        autoCreate,
        isAutoPay,
        isActive,
        nextDate,
        lastPaidDate,
        lastGenerated,
        billContext,
      ];
}
