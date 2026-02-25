import '../models/recurring_transaction.dart';

/// Represents a scheduled/recurring bill payment (rent, electricity, subscriptions, etc.).
class Bill {
  Bill({
    this.id,
    required this.name,
    required this.amount,
    this.category = 'Bills & Utilities',
    this.frequency = RecurringFrequency.monthly,
    this.dueDay = 1,
    this.isAutoPay = false,
    this.isActive = true,
    this.notes,
    this.paymentMethod,
    this.lastPaidDate,
    DateTime? createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String name;
  final double amount;
  final String category;
  final RecurringFrequency frequency;
  final int dueDay; // 1–28
  final bool isAutoPay;
  final bool isActive;
  final String? notes;
  final String? paymentMethod;
  final DateTime? lastPaidDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  // ── Computed Properties ──

  /// The next due date for this bill, based on [frequency] and [dueDay].
  DateTime get nextDueDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (frequency) {
      case RecurringFrequency.monthly:
        var due = DateTime(now.year, now.month, dueDay);
        if (due.isBefore(today) || due.isAtSameMomentAs(today)) {
          // If already passed (or today) and paid this period, move to next month
          if (isPaidThisPeriod) {
            due = DateTime(now.year, now.month + 1, dueDay);
          }
        }
        return due;

      case RecurringFrequency.quarterly:
        // Quarter months: 1, 4, 7, 10
        final quarterStart = ((now.month - 1) ~/ 3) * 3 + 1;
        var due = DateTime(now.year, quarterStart, dueDay);
        if (due.isBefore(today) && isPaidThisPeriod) {
          due = DateTime(now.year, quarterStart + 3, dueDay);
        }
        return due;

      case RecurringFrequency.yearly:
        var due = DateTime(now.year, 1, dueDay);
        if (due.isBefore(today) && isPaidThisPeriod) {
          due = DateTime(now.year + 1, 1, dueDay);
        }
        return due;

      case RecurringFrequency.weekly:
        // dueDay as weekday (1=Mon, 7=Sun)
        final diff = (dueDay - now.weekday + 7) % 7;
        var due = today.add(Duration(days: diff == 0 && isPaidThisPeriod ? 7 : diff));
        return due;

      case RecurringFrequency.biweekly:
        final diff = (dueDay - now.weekday + 14) % 14;
        return today.add(Duration(days: diff == 0 && isPaidThisPeriod ? 14 : diff));

      case RecurringFrequency.daily:
        return isPaidThisPeriod ? today.add(const Duration(days: 1)) : today;
    }
  }

  /// Whether the bill has been paid for the current billing period.
  bool get isPaidThisPeriod {
    if (lastPaidDate == null) return false;
    final now = DateTime.now();
    final paid = lastPaidDate!;

    switch (frequency) {
      case RecurringFrequency.daily:
        return paid.year == now.year &&
            paid.month == now.month &&
            paid.day == now.day;
      case RecurringFrequency.weekly:
        return now.difference(paid).inDays < 7;
      case RecurringFrequency.biweekly:
        return now.difference(paid).inDays < 14;
      case RecurringFrequency.monthly:
        return paid.year == now.year && paid.month == now.month;
      case RecurringFrequency.quarterly:
        final paidQ = ((paid.month - 1) ~/ 3);
        final nowQ = ((now.month - 1) ~/ 3);
        return paid.year == now.year && paidQ == nowQ;
      case RecurringFrequency.yearly:
        return paid.year == now.year;
    }
  }

  /// Whether the bill is overdue (past due date and unpaid this period).
  bool get isOverdue {
    if (!isActive || isPaidThisPeriod) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // For monthly: overdue if we're past the due day and haven't paid
    if (frequency == RecurringFrequency.monthly) {
      final due = DateTime(now.year, now.month, dueDay);
      return today.isAfter(due);
    }
    return nextDueDate.isBefore(today);
  }

  /// Days until next due date (+ve = upcoming, -ve = overdue).
  int get daysUntilDue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return nextDueDate.difference(today).inDays;
  }

  // ── Serialization ──

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'amount': amount,
      'category': category,
      'frequency': frequency.dbValue,
      'due_day': dueDay,
      'is_auto_pay': isAutoPay ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'notes': notes,
      'payment_method': paymentMethod,
      'last_paid_date': lastPaidDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as int?,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String? ?? 'Bills & Utilities',
      frequency: RecurringFrequency.fromDb(
          map['frequency'] as String? ?? 'monthly'),
      dueDay: map['due_day'] as int? ?? 1,
      isAutoPay: (map['is_auto_pay'] as int?) == 1,
      isActive: (map['is_active'] as int?) != 0,
      notes: map['notes'] as String?,
      paymentMethod: map['payment_method'] as String?,
      lastPaidDate: map['last_paid_date'] != null
          ? DateTime.parse(map['last_paid_date'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Bill copyWith({
    int? id,
    String? name,
    double? amount,
    String? category,
    RecurringFrequency? frequency,
    int? dueDay,
    bool? isAutoPay,
    bool? isActive,
    String? notes,
    String? paymentMethod,
    DateTime? lastPaidDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Bill(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      frequency: frequency ?? this.frequency,
      dueDay: dueDay ?? this.dueDay,
      isAutoPay: isAutoPay ?? this.isAutoPay,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      lastPaidDate: lastPaidDate ?? this.lastPaidDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  String toString() => 'Bill(id=$id, name=$name, ₹$amount, '
      'due=$dueDay, freq=${frequency.label}, '
      'paid=${isPaidThisPeriod ? "yes" : "no"})';
}
