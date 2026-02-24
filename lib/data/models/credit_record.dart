import 'package:equatable/equatable.dart';

/// A credit record (udhar/khata) — money lent to a customer.
class CreditRecord extends Equatable {
  const CreditRecord({
    this.id,
    required this.customerName,
    this.customerId,
    this.phoneNumber,
    required this.totalAmount,
    this.paidAmount = 0,
    required this.pendingAmount,
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

  /// Progress of repayment (0.0 to 1.0).
  double get repaymentProgress =>
      totalAmount > 0 ? (paidAmount / totalAmount).clamp(0.0, 1.0) : 0.0;

  /// Returns true if due date is past and not cleared.
  bool get computedOverdue {
    if (isCleared) return false;
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  CreditRecord copyWith({
    int? id,
    String? customerName,
    int? customerId,
    String? phoneNumber,
    double? totalAmount,
    double? paidAmount,
    double? pendingAmount,
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
  List<Object?> get props => [id, customerName, totalAmount, creditDate];
}
