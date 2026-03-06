/// Direction of a credit entry: money given (diya) or received (liya).
enum CreditDirection {
  given('Given (Diya)', 'given'),
  received('Received (Liya)', 'received');

  const CreditDirection(this.label, this.dbValue);
  final String label;
  final String dbValue;

  static CreditDirection fromDb(String? value) {
    if (value == null) return CreditDirection.given;
    return CreditDirection.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => CreditDirection.given,
    );
  }
}

/// Interest type for a credit entry.
enum CreditInterestType {
  none('None', 'none'),
  simple('Simple', 'simple'),
  compound('Compound', 'compound');

  const CreditInterestType(this.label, this.dbValue);
  final String label;
  final String dbValue;

  static CreditInterestType fromDb(String? value) {
    if (value == null) return CreditInterestType.none;
    return CreditInterestType.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => CreditInterestType.none,
    );
  }
}

/// A single credit / udhar entry (given or received).
///
/// [businessId] == null  → personal credit  
/// [businessId] == N     → credit belongs to Business N
class Credit {
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
  final CreditInterestType interestType;
  final String? notes;
  final String? tags;

  /// `null` = personal; non-null = belongs to this business.
  final int? businessId;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  Credit({
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
    this.interestType = CreditInterestType.none,
    this.notes,
    this.tags,
    this.businessId,
    DateTime? createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether this is money you gave to someone (they owe you).
  bool get isGiven => direction == CreditDirection.given;

  /// Whether this is money you received (you owe them).
  bool get isReceived => direction == CreditDirection.received;

  /// Progress fraction (0.0 – 1.0).
  double get progress =>
      totalAmount > 0 ? (paidAmount / totalAmount).clamp(0.0, 1.0) : 0;

  /// Days until due. Negative means overdue.
  int? get daysUntilDue => dueDate?.difference(DateTime.now()).inDays;

  /// Whether this belongs to a business context.
  bool get isBusiness => businessId != null;

  /// Whether this is a personal credit (not tied to any business).
  bool get isPersonal => businessId == null;

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
      'interest_type': interestType.dbValue,
      'notes': notes,
      'tags': tags,
      'business_id': businessId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Credit.fromMap(Map<String, dynamic> map) {
    return Credit(
      id: map['id'] as int?,
      customerName: map['customer_name'] as String,
      customerId: map['customer_id'] as int?,
      phoneNumber: map['phone_number'] as String?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      pendingAmount: (map['pending_amount'] as num).toDouble(),
      direction: CreditDirection.fromDb(map['direction'] as String?),
      creditDate: DateTime.parse(map['credit_date'] as String),
      dueDate: map['due_date'] != null
          ? DateTime.parse(map['due_date'] as String)
          : null,
      clearedDate: map['cleared_date'] != null
          ? DateTime.parse(map['cleared_date'] as String)
          : null,
      isCleared: (map['is_cleared'] as int?) == 1,
      isOverdue: (map['is_overdue'] as int?) == 1,
      interestRate: (map['interest_rate'] as num?)?.toDouble(),
      interestType: CreditInterestType.fromDb(map['interest_type'] as String?),
      notes: map['notes'] as String?,
      tags: map['tags'] as String?,
      businessId: map['business_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Credit copyWith({
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
    CreditInterestType? interestType,
    String? notes,
    String? tags,
    int? businessId,
    DateTime? updatedAt,
  }) {
    return Credit(
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
      businessId: businessId ?? this.businessId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt,
    );
  }

  @override
  String toString() =>
      'Credit(id: $id, customerName: $customerName, direction: ${direction.dbValue}, '
      'pending: $pendingAmount, business: $businessId)';
}
