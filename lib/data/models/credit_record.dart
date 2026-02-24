import 'package:equatable/equatable.dart';

/// Direction of credit — given to someone or received from someone.
enum CreditDirection {
  given,    // You lent money (udhar diya)
  received; // You borrowed money (udhar liya)

  String get label {
    switch (this) {
      case CreditDirection.given:
        return 'Credit Given';
      case CreditDirection.received:
        return 'Credit Received';
    }
  }

  String get shortLabel {
    switch (this) {
      case CreditDirection.given:
        return 'Given';
      case CreditDirection.received:
        return 'Received';
    }
  }

  String get dbValue => name;

  static CreditDirection fromDb(String value) {
    return CreditDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CreditDirection.given,
    );
  }
}

/// A credit record (udhar/khata) — money lent to or borrowed from a party.
class CreditRecord extends Equatable {
  const CreditRecord({
    this.id,
    required this.customerName,
    this.customerId,
    this.phoneNumber,
    required this.totalAmount,
    this.paidAmount = 0,
    required this.pendingAmount,
    this.direction = CreditDirection.given,
    required this.creditDate,
    this.dueDate,
    this.clearedDate,
    this.isCleared = false,
    this.isOverdue = false,
    this.interestRate,
    this.interestType,
    this.notes,
    this.tags,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final String customerName;
  final int? customerId;
  final String? phoneNumber;
  final double totalAmount;
  final double paidAmount;
  final double pendingAmount;
  final CreditDirection direction;
  final DateTime creditDate;
  final DateTime? dueDate;
  final DateTime? clearedDate;
  final bool isCleared;
  final bool isOverdue;
  final double? interestRate;
  final String? interestType;
  final String? notes;
  final List<String>? tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Whether this is credit given to someone.
  bool get isGiven => direction == CreditDirection.given;

  /// Whether this is credit received from someone.
  bool get isReceived => direction == CreditDirection.received;

  /// Progress of repayment (0.0 to 1.0).
  double get repaymentProgress =>
      totalAmount > 0 ? (paidAmount / totalAmount).clamp(0.0, 1.0) : 0.0;

  /// Returns true if due date is past and not cleared.
  bool get computedOverdue {
    if (isCleared) return false;
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// Days remaining until due date. Negative if overdue.
  int? get daysUntilDue {
    if (dueDate == null) return null;
    return dueDate!.difference(DateTime.now()).inDays;
  }

  CreditRecord copyWith({
    int? id,
    String? customerName,
    int? customerId,
    String? phoneNumber,
    double? totalAmount,
    double? paidAmount,
    double? pendingAmount,
    CreditDirection? direction,
    DateTime? creditDate,
    DateTime? dueDate,
    DateTime? clearedDate,
    bool? isCleared,
    bool? isOverdue,
    double? interestRate,
    String? interestType,
    String? notes,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return CreditRecord(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerId: customerId ?? this.customerId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      direction: direction ?? this.direction,
      creditDate: creditDate ?? this.creditDate,
      dueDate: dueDate ?? this.dueDate,
      clearedDate: clearedDate ?? this.clearedDate,
      isCleared: isCleared ?? this.isCleared,
      isOverdue: isOverdue ?? this.isOverdue,
      interestRate: interestRate ?? this.interestRate,
      interestType: interestType ?? this.interestType,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_name': customerName,
      'customer_id': customerId,
      'phone_number': phoneNumber,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'pending_amount': pendingAmount,
      'direction': direction.dbValue,
      'credit_date': creditDate.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'cleared_date': clearedDate?.toIso8601String(),
      'is_cleared': isCleared ? 1 : 0,
      'is_overdue': isOverdue ? 1 : 0,
      'interest_rate': interestRate,
      'interest_type': interestType,
      'notes': notes,
      'tags': tags?.join(','),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory CreditRecord.fromMap(Map<String, dynamic> map) {
    return CreditRecord(
      id: map['id'] as int?,
      customerName: map['customer_name'] as String,
      customerId: map['customer_id'] as int?,
      phoneNumber: map['phone_number'] as String?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num? ?? 0).toDouble(),
      pendingAmount: (map['pending_amount'] as num).toDouble(),
      direction: CreditDirection.fromDb(map['direction'] as String? ?? 'given'),
      creditDate: DateTime.parse(map['credit_date'] as String),
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date'] as String) : null,
      clearedDate: map['cleared_date'] != null ? DateTime.parse(map['cleared_date'] as String) : null,
      isCleared: (map['is_cleared'] as int? ?? 0) == 1,
      isOverdue: (map['is_overdue'] as int? ?? 0) == 1,
      interestRate: (map['interest_rate'] as num?)?.toDouble(),
      interestType: map['interest_type'] as String?,
      notes: map['notes'] as String?,
      tags: (map['tags'] as String?)?.split(',').where((t) => t.isNotEmpty).toList(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [id, customerName, totalAmount, creditDate, direction];
}

/// A payment against a credit record.
class CreditPayment extends Equatable {
  const CreditPayment({
    this.id,
    required this.creditId,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod,
    this.transactionId,
    this.notes,
    this.createdAt,
  });

  final int? id;
  final int creditId;
  final double amount;
  final DateTime paymentDate;
  final String? paymentMethod;
  final int? transactionId; // Link to detected SMS transaction
  final String? notes;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'credit_id': creditId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'payment_method': paymentMethod,
      'transaction_id': transactionId,
      'notes': notes,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory CreditPayment.fromMap(Map<String, dynamic> map) {
    return CreditPayment(
      id: map['id'] as int?,
      creditId: map['credit_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      paymentDate: DateTime.parse(map['payment_date'] as String),
      paymentMethod: map['payment_method'] as String?,
      transactionId: map['transaction_id'] as int?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, creditId, amount, paymentDate];
}
