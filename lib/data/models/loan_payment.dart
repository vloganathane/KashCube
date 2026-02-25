/// Represents a single scheduled installment in a loan repayment schedule.
class LoanPayment {
  final int? id;
  final int loanId;
  final int installmentNumber;
  final DateTime dueDate;
  final double amount;
  final double paidAmount;
  final bool isPaid;
  final DateTime? paidDate;
  final String? notes;
  final DateTime createdAt;

  LoanPayment({
    this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.dueDate,
    required this.amount,
    this.paidAmount = 0,
    this.isPaid = false,
    this.paidDate,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether this installment is overdue (unpaid and past due date).
  bool get isOverdue =>
      !isPaid && dueDate.isBefore(DateTime.now());

  /// Remaining amount for this installment.
  double get remainingAmount => (amount - paidAmount).clamp(0, double.infinity);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'loan_id': loanId,
      'installment_number': installmentNumber,
      'due_date': dueDate.toIso8601String(),
      'amount': amount,
      'paid_amount': paidAmount,
      'is_paid': isPaid ? 1 : 0,
      'paid_date': paidDate?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory LoanPayment.fromMap(Map<String, dynamic> map) {
    return LoanPayment(
      id: map['id'] as int?,
      loanId: map['loan_id'] as int,
      installmentNumber: map['installment_number'] as int,
      dueDate: DateTime.parse(map['due_date'] as String),
      amount: (map['amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      isPaid: (map['is_paid'] as int?) == 1,
      paidDate: map['paid_date'] != null
          ? DateTime.parse(map['paid_date'] as String)
          : null,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  LoanPayment copyWith({
    int? id,
    int? loanId,
    int? installmentNumber,
    DateTime? dueDate,
    double? amount,
    double? paidAmount,
    bool? isPaid,
    DateTime? paidDate,
    String? notes,
  }) {
    return LoanPayment(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      installmentNumber: installmentNumber ?? this.installmentNumber,
      dueDate: dueDate ?? this.dueDate,
      amount: amount ?? this.amount,
      paidAmount: paidAmount ?? this.paidAmount,
      isPaid: isPaid ?? this.isPaid,
      paidDate: paidDate ?? this.paidDate,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}
