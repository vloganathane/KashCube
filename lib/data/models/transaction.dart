import 'package:equatable/equatable.dart';

/// Represents the type of a financial transaction.
enum TransactionType {
  income,
  expense,
  creditGiven,
  creditReceived,
  loanTaken,
  loanRepayment;

  String get label {
    switch (this) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.creditGiven:
        return 'Credit Given';
      case TransactionType.creditReceived:
        return 'Credit Received';
      case TransactionType.loanTaken:
        return 'Loan Taken';
      case TransactionType.loanRepayment:
        return 'Loan Repayment';
    }
  }

  String get dbValue {
    switch (this) {
      case TransactionType.income:
        return 'income';
      case TransactionType.expense:
        return 'expense';
      case TransactionType.creditGiven:
        return 'credit_given';
      case TransactionType.creditReceived:
        return 'credit_received';
      case TransactionType.loanTaken:
        return 'loan_taken';
      case TransactionType.loanRepayment:
        return 'loan_repayment';
    }
  }

  static TransactionType fromDb(String value) {
    switch (value) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      case 'credit_given':
        return TransactionType.creditGiven;
      case 'credit_received':
        return TransactionType.creditReceived;
      case 'loan_taken':
        return TransactionType.loanTaken;
      case 'loan_repayment':
        return TransactionType.loanRepayment;
      default:
        return TransactionType.expense;
    }
  }
}

/// Represents the mode of a transaction.
enum TransactionMode {
  personal,
  business,
  investment;

  String get label {
    switch (this) {
      case TransactionMode.personal:
        return 'Personal';
      case TransactionMode.business:
        return 'Business';
      case TransactionMode.investment:
        return 'Investment';
    }
  }
}

/// Payment method used for the transaction.
enum PaymentMethod {
  upi,
  cash,
  creditCard,
  debitCard,
  netBanking,
  wallet,
  cheque;

  String get label {
    switch (this) {
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.creditCard:
        return 'Credit Card';
      case PaymentMethod.debitCard:
        return 'Debit Card';
      case PaymentMethod.netBanking:
        return 'Net Banking';
      case PaymentMethod.wallet:
        return 'Wallet';
      case PaymentMethod.cheque:
        return 'Cheque';
    }
  }

  String get dbValue => name;

  static PaymentMethod fromDb(String value) {
    return PaymentMethod.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

/// A financial transaction record.
class Transaction extends Equatable {
  const Transaction({
    this.id,
    required this.amount,
    required this.date,
    required this.type,
    this.mode = TransactionMode.personal,
    required this.category,
    this.partyName,
    this.partyId,
    this.phoneNumber,
    this.paymentMethod = PaymentMethod.cash,
    this.accountId,
    this.smsBody,
    this.smsSender,
    this.upiApp,
    this.upiRefNo,
    this.referenceId,
    this.autoDetected = false,
    this.verified = false,
    this.creditId,
    this.loanId,
    this.parentTransactionId,
    this.dedupeHash,
    this.notes,
    this.tags,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final TransactionMode mode;
  final String category;
  final String? partyName;
  final int? partyId;
  final String? phoneNumber;
  final PaymentMethod paymentMethod;
  final int? accountId;
  final String? smsBody;
  final String? smsSender;
  final String? upiApp;
  final String? upiRefNo;
  final String? referenceId;
  final bool autoDetected;
  final bool verified;
  final int? creditId;
  final int? loanId;
  final int? parentTransactionId;
  final String? dedupeHash;
  final String? notes;
  final List<String>? tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Whether this is a money-in transaction.
  bool get isIncome =>
      type == TransactionType.income ||
      type == TransactionType.creditReceived ||
      type == TransactionType.loanTaken;

  /// Whether this is a money-out transaction.
  bool get isExpense =>
      type == TransactionType.expense ||
      type == TransactionType.creditGiven ||
      type == TransactionType.loanRepayment;

  /// Creates a copy with updated fields.
  Transaction copyWith({
    int? id,
    double? amount,
    DateTime? date,
    TransactionType? type,
    TransactionMode? mode,
    String? category,
    String? partyName,
    int? partyId,
    String? phoneNumber,
    PaymentMethod? paymentMethod,
    int? accountId,
    String? smsBody,
    String? smsSender,
    String? upiApp,
    String? upiRefNo,
    String? referenceId,
    bool? autoDetected,
    bool? verified,
    int? creditId,
    int? loanId,
    int? parentTransactionId,
    String? dedupeHash,
    String? notes,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      type: type ?? this.type,
      mode: mode ?? this.mode,
      category: category ?? this.category,
      partyName: partyName ?? this.partyName,
      partyId: partyId ?? this.partyId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      accountId: accountId ?? this.accountId,
      smsBody: smsBody ?? this.smsBody,
      smsSender: smsSender ?? this.smsSender,
      upiApp: upiApp ?? this.upiApp,
      upiRefNo: upiRefNo ?? this.upiRefNo,
      referenceId: referenceId ?? this.referenceId,
      autoDetected: autoDetected ?? this.autoDetected,
      verified: verified ?? this.verified,
      creditId: creditId ?? this.creditId,
      loanId: loanId ?? this.loanId,
      parentTransactionId: parentTransactionId ?? this.parentTransactionId,
      dedupeHash: dedupeHash ?? this.dedupeHash,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  /// Convert to a map for database insertion.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'date': date.toIso8601String(),
      'type': type.dbValue,
      'mode': mode.name,
      'category': category,
      'party_name': partyName,
      'party_id': partyId,
      'phone_number': phoneNumber,
      'payment_method': paymentMethod.dbValue,
      'account_id': accountId,
      'sms_body': smsBody,
      'sms_sender': smsSender,
      'upi_app': upiApp,
      'upi_ref_no': upiRefNo,
      'reference_id': referenceId,
      'auto_detected': autoDetected ? 1 : 0,
      'verified': verified ? 1 : 0,
      'credit_id': creditId,
      'loan_id': loanId,
      'parent_transaction_id': parentTransactionId,
      'dedupe_hash': dedupeHash,
      'notes': notes,
      'tags': tags?.join(','),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  /// Create a Transaction from a database row.
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      type: TransactionType.fromDb(map['type'] as String),
      mode: TransactionMode.values.firstWhere(
        (e) => e.name == (map['mode'] as String? ?? 'personal'),
        orElse: () => TransactionMode.personal,
      ),
      category: map['category'] as String,
      partyName: map['party_name'] as String?,
      partyId: map['party_id'] as int?,
      phoneNumber: map['phone_number'] as String?,
      paymentMethod: PaymentMethod.fromDb(map['payment_method'] as String? ?? 'cash'),
      accountId: map['account_id'] as int?,
      smsBody: map['sms_body'] as String?,
      smsSender: map['sms_sender'] as String?,
      upiApp: map['upi_app'] as String?,
      upiRefNo: map['upi_ref_no'] as String?,
      referenceId: map['reference_id'] as String?,
      autoDetected: (map['auto_detected'] as int? ?? 0) == 1,
      verified: (map['verified'] as int? ?? 0) == 1,
      creditId: map['credit_id'] as int?,
      loanId: map['loan_id'] as int?,
      parentTransactionId: map['parent_transaction_id'] as int?,
      dedupeHash: map['dedupe_hash'] as String?,
      notes: map['notes'] as String?,
      tags: (map['tags'] as String?)?.split(',').where((t) => t.isNotEmpty).toList(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [id, amount, date, type, category, dedupeHash];
}
