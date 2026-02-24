/// Represents the type of interest on a loan.
enum InterestType {
  none('None', 'none'),
  simple('Simple', 'simple'),
  compound('Compound', 'compound');

  const InterestType(this.label, this.dbValue);
  final String label;
  final String dbValue;

  static InterestType fromDb(String? value) {
    if (value == null) return InterestType.none;
    return InterestType.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => InterestType.none,
    );
  }
}

/// A loan record (taken from a lender).
class Loan {
  final int? id;
  final String lenderName;
  final int? lenderId;
  final String? phoneNumber;
  final double principalAmount;
  final double paidAmount;
  final double pendingAmount;
  final DateTime loanDate;
  final DateTime? dueDate;
  final DateTime? clearedDate;
  final bool isCleared;
  final bool isOverdue;
  final double? emiAmount;
  final int? totalEmis;
  final int paidEmis;
  final int? emiDay;
  final DateTime? nextEmiDate;
  final double? interestRate;
  final InterestType interestType;
  final double? totalInterest;
  final String? notes;
  final String? tags;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  Loan({
    this.id,
    required this.lenderName,
    this.lenderId,
    this.phoneNumber,
    required this.principalAmount,
    this.paidAmount = 0,
    required this.pendingAmount,
    required this.loanDate,
    this.dueDate,
    this.clearedDate,
    this.isCleared = false,
    this.isOverdue = false,
    this.emiAmount,
    this.totalEmis,
    this.paidEmis = 0,
    this.emiDay,
    this.nextEmiDate,
    this.interestRate,
    this.interestType = InterestType.none,
    this.totalInterest,
    this.notes,
    this.tags,
    DateTime? createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Progress fraction (0.0 – 1.0).
  double get progress =>
      principalAmount > 0 ? (paidAmount / principalAmount).clamp(0, 1) : 0;

  /// Days until due. Negative means overdue.
  int? get daysUntilDue =>
      dueDate?.difference(DateTime.now()).inDays;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'lender_name': lenderName,
      'lender_id': lenderId,
      'phone_number': phoneNumber,
      'principal_amount': principalAmount,
      'paid_amount': paidAmount,
      'pending_amount': pendingAmount,
      'loan_date': loanDate.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'cleared_date': clearedDate?.toIso8601String(),
      'is_cleared': isCleared ? 1 : 0,
      'is_overdue': isOverdue ? 1 : 0,
      'emi_amount': emiAmount,
      'total_emis': totalEmis,
      'paid_emis': paidEmis,
      'emi_day': emiDay,
      'next_emi_date': nextEmiDate?.toIso8601String(),
      'interest_rate': interestRate,
      'interest_type': interestType.dbValue,
      'total_interest': totalInterest,
      'notes': notes,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id'] as int?,
      lenderName: map['lender_name'] as String,
      lenderId: map['lender_id'] as int?,
      phoneNumber: map['phone_number'] as String?,
      principalAmount: (map['principal_amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      pendingAmount: (map['pending_amount'] as num).toDouble(),
      loanDate: DateTime.parse(map['loan_date'] as String),
      dueDate: map['due_date'] != null
          ? DateTime.parse(map['due_date'] as String)
          : null,
      clearedDate: map['cleared_date'] != null
          ? DateTime.parse(map['cleared_date'] as String)
          : null,
      isCleared: (map['is_cleared'] as int?) == 1,
      isOverdue: (map['is_overdue'] as int?) == 1,
      emiAmount: (map['emi_amount'] as num?)?.toDouble(),
      totalEmis: map['total_emis'] as int?,
      paidEmis: (map['paid_emis'] as int?) ?? 0,
      emiDay: map['emi_day'] as int?,
      nextEmiDate: map['next_emi_date'] != null
          ? DateTime.parse(map['next_emi_date'] as String)
          : null,
      interestRate: (map['interest_rate'] as num?)?.toDouble(),
      interestType: InterestType.fromDb(map['interest_type'] as String?),
      totalInterest: (map['total_interest'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      tags: map['tags'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Loan copyWith({
    int? id,
    String? lenderName,
    int? lenderId,
    String? phoneNumber,
    double? principalAmount,
    double? paidAmount,
    double? pendingAmount,
    DateTime? loanDate,
    DateTime? dueDate,
    DateTime? clearedDate,
    bool? isCleared,
    bool? isOverdue,
    double? emiAmount,
    int? totalEmis,
    int? paidEmis,
    int? emiDay,
    DateTime? nextEmiDate,
    double? interestRate,
    InterestType? interestType,
    double? totalInterest,
    String? notes,
    String? tags,
  }) {
    return Loan(
      id: id ?? this.id,
      lenderName: lenderName ?? this.lenderName,
      lenderId: lenderId ?? this.lenderId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      principalAmount: principalAmount ?? this.principalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      loanDate: loanDate ?? this.loanDate,
      dueDate: dueDate ?? this.dueDate,
      clearedDate: clearedDate ?? this.clearedDate,
      isCleared: isCleared ?? this.isCleared,
      isOverdue: isOverdue ?? this.isOverdue,
      emiAmount: emiAmount ?? this.emiAmount,
      totalEmis: totalEmis ?? this.totalEmis,
      paidEmis: paidEmis ?? this.paidEmis,
      emiDay: emiDay ?? this.emiDay,
      nextEmiDate: nextEmiDate ?? this.nextEmiDate,
      interestRate: interestRate ?? this.interestRate,
      interestType: interestType ?? this.interestType,
      totalInterest: totalInterest ?? this.totalInterest,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
