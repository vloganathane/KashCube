import 'package:equatable/equatable.dart';

/// Represents the type of a financial transaction (unified model).
///
/// All financial events — spending, earning, lending, borrowing,
/// investing, and settlements — are stored as transactions with
/// one of these types.
enum TransactionType {
  income,
  expense,
  lent,
  borrowed,
  invested,
  receivedBack,
  paidBack,
  redeemed,
  transfer;

  String get label {
    switch (this) {
      case TransactionType.income:
        return 'Earned';
      case TransactionType.expense:
        return 'Spent';
      case TransactionType.lent:
        return 'Lent';
      case TransactionType.borrowed:
        return 'Borrowed';
      case TransactionType.invested:
        return 'Invested';
      case TransactionType.receivedBack:
        return 'Received Back';
      case TransactionType.paidBack:
        return 'Paid Back';
      case TransactionType.redeemed:
        return 'Redeemed';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  String get dbValue {
    switch (this) {
      case TransactionType.income:
        return 'income';
      case TransactionType.expense:
        return 'expense';
      case TransactionType.lent:
        return 'lent';
      case TransactionType.borrowed:
        return 'borrowed';
      case TransactionType.invested:
        return 'invested';
      case TransactionType.receivedBack:
        return 'received_back';
      case TransactionType.paidBack:
        return 'paid_back';
      case TransactionType.redeemed:
        return 'redeemed';
      case TransactionType.transfer:
        return 'transfer';
    }
  }

  static TransactionType fromDb(String value) {
    switch (value) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      case 'lent':
        return TransactionType.lent;
      case 'borrowed':
        return TransactionType.borrowed;
      case 'invested':
        return TransactionType.invested;
      case 'received_back':
        return TransactionType.receivedBack;
      case 'paid_back':
        return TransactionType.paidBack;
      case 'redeemed':
        return TransactionType.redeemed;
      // Legacy V6 migration fallbacks
      case 'credit_given':
        return TransactionType.lent;
      case 'credit_received':
        return TransactionType.borrowed;
      case 'loan_taken':
        return TransactionType.borrowed;
      case 'loan_repayment':
        return TransactionType.paidBack;
      case 'transfer':
        return TransactionType.transfer;
      default:
        return TransactionType.expense;
    }
  }

  bool get isIncome =>
      this == TransactionType.income ||
      this == TransactionType.receivedBack ||
      this == TransactionType.redeemed;

  bool get isExpense =>
      this == TransactionType.expense || this == TransactionType.paidBack;

  bool get isLending =>
      this == TransactionType.lent ||
      this == TransactionType.borrowed ||
      this == TransactionType.receivedBack ||
      this == TransactionType.paidBack;

  bool get isSettlement =>
      this == TransactionType.receivedBack || this == TransactionType.paidBack;

  bool get isInvestment =>
      this == TransactionType.invested || this == TransactionType.redeemed;

  bool get isTransfer => this == TransactionType.transfer;

  bool get requiresParty => isLending || isInvestment;
}

/// Represents the mode of a transaction.
enum TransactionMode {
  personal,
  business;

  String get label {
    switch (this) {
      case TransactionMode.personal:
        return 'Personal';
      case TransactionMode.business:
        return 'Business';
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

/// Type of interest on a lending/borrowing transaction.
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

/// Frequency at which loan installments are due.
enum RepaymentFrequency {
  daily('Daily', 'daily'),
  weekly('Weekly', 'weekly'),
  monthly('Monthly', 'monthly');

  const RepaymentFrequency(this.label, this.dbValue);
  final String label;
  final String dbValue;

  static RepaymentFrequency? fromDb(String? value) {
    if (value == null) return null;
    return RepaymentFrequency.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => RepaymentFrequency.monthly,
    );
  }
}

/// A unified financial transaction record.
///
/// This model covers ALL financial events: income, expense, lending,
/// borrowing, investment, and settlements. Lending/borrowing fields
/// are nullable and only populated for those transaction types.
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
    this.toAccountId,
    this.smsBody,
    this.smsSender,
    this.upiApp,
    this.upiRefNo,
    this.referenceId,
    this.autoDetected = false,
    this.verified = false,
    this.linkedTransactionId,
    this.parentTransactionId,
    // Lending/borrowing fields
    this.loanId,
    this.dueDate,
    this.interestRate,
    this.interestType,
    this.repaymentFrequency,
    this.totalInstallments,
    this.emiAmount,
    this.dedupeHash,
    this.notes,
    this.tags,
    this.reminderSentAt,
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
  /// For transfer type: the destination account.
  final int? toAccountId;
  final String? smsBody;
  final String? smsSender;
  final String? upiApp;
  final String? upiRefNo;
  final String? referenceId;
  final bool autoDetected;
  final bool verified;

  /// For settlement types (receivedBack/paidBack/redeemed):
  /// links back to the original lent/borrowed/invested transaction.
  final int? linkedTransactionId;

  /// For recurring / split transactions.
  final int? parentTransactionId;

  // --- Lending / Borrowing fields (nullable) ---

  /// When this lent/borrowed amount is due.
  final DateTime? dueDate;

  /// Annual interest rate (e.g., 12.0 for 12%).
  final double? interestRate;

  /// Type of interest calculation.
  final InterestType? interestType;

  /// How often installments are due.
  final RepaymentFrequency? repaymentFrequency;

  /// Total number of installments/EMIs.
  final int? totalInstallments;

  /// Per-installment EMI amount.
  final double? emiAmount;

  /// Foreign key to the [loans] table when this transaction was auto-created by a Loan contract.
  /// Null for regular transactions. Set to prevent manual editing.
  final int? loanId;

  final String? dedupeHash;
  final String? notes;
  final List<String>? tags;
  /// When the last reminder (WhatsApp/SMS/Email) was sent for this transaction.
  /// Only set on [TransactionType.lent] and [TransactionType.borrowed] transactions.
  final DateTime? reminderSentAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Whether this is a money-in transaction.
  bool get isIncome =>
      type == TransactionType.income ||
      type == TransactionType.receivedBack ||
      type == TransactionType.redeemed;

  /// Whether this is a money-out transaction.
  bool get isExpense =>
      type == TransactionType.expense ||
      type == TransactionType.lent ||
      type == TransactionType.invested ||
      type == TransactionType.paidBack;

  /// Whether this is a lending/borrowing event.
  bool get isLending =>
      type == TransactionType.lent || type == TransactionType.borrowed;

  /// Whether this is a settlement (paying back / receiving back).
  bool get isSettlement =>
      type == TransactionType.receivedBack ||
      type == TransactionType.paidBack;

  /// Whether this is an investment event.
  bool get isInvestment =>
      type == TransactionType.invested || type == TransactionType.redeemed;

  /// Whether this type requires a party name.
  bool get requiresParty => isLending || isSettlement;

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
    int? toAccountId,
    String? smsBody,
    String? smsSender,
    String? upiApp,
    String? upiRefNo,
    String? referenceId,
    bool? autoDetected,
    bool? verified,
    int? linkedTransactionId,
    int? parentTransactionId,
    DateTime? dueDate,
    double? interestRate,
    InterestType? interestType,
    RepaymentFrequency? repaymentFrequency,
    int? totalInstallments,
    double? emiAmount,
    int? loanId,
    String? dedupeHash,
    String? notes,
    List<String>? tags,
    DateTime? reminderSentAt,
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
      toAccountId: toAccountId ?? this.toAccountId,
      smsBody: smsBody ?? this.smsBody,
      smsSender: smsSender ?? this.smsSender,
      upiApp: upiApp ?? this.upiApp,
      upiRefNo: upiRefNo ?? this.upiRefNo,
      referenceId: referenceId ?? this.referenceId,
      autoDetected: autoDetected ?? this.autoDetected,
      verified: verified ?? this.verified,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
      parentTransactionId: parentTransactionId ?? this.parentTransactionId,
      dueDate: dueDate ?? this.dueDate,
      interestRate: interestRate ?? this.interestRate,
      interestType: interestType ?? this.interestType,
      repaymentFrequency: repaymentFrequency ?? this.repaymentFrequency,
      totalInstallments: totalInstallments ?? this.totalInstallments,
      emiAmount: emiAmount ?? this.emiAmount,
      loanId: loanId ?? this.loanId,
      dedupeHash: dedupeHash ?? this.dedupeHash,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      reminderSentAt: reminderSentAt ?? this.reminderSentAt,
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
      'to_account_id': toAccountId,
      'sms_body': smsBody,
      'sms_sender': smsSender,
      'upi_app': upiApp,
      'upi_ref_no': upiRefNo,
      'reference_id': referenceId,
      'auto_detected': autoDetected ? 1 : 0,
      'verified': verified ? 1 : 0,
      'linked_transaction_id': linkedTransactionId,
      'parent_transaction_id': parentTransactionId,
      'due_date': dueDate?.toIso8601String(),
      'interest_rate': interestRate,
      'interest_type': interestType?.dbValue,
      'repayment_frequency': repaymentFrequency?.dbValue,
      'total_installments': totalInstallments,
      'emi_amount': emiAmount,
      'loan_id': loanId,
      'dedupe_hash': dedupeHash,
      'notes': notes,
      'tags': tags?.join(','),
      'reminder_sent_at': reminderSentAt?.toIso8601String(),
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
      paymentMethod:
          PaymentMethod.fromDb(map['payment_method'] as String? ?? 'cash'),
      accountId: map['account_id'] as int?,
      toAccountId: map['to_account_id'] as int?,
      smsBody: map['sms_body'] as String?,
      smsSender: map['sms_sender'] as String?,
      upiApp: map['upi_app'] as String?,
      upiRefNo: map['upi_ref_no'] as String?,
      referenceId: map['reference_id'] as String?,
      autoDetected: (map['auto_detected'] as int? ?? 0) == 1,
      verified: (map['verified'] as int? ?? 0) == 1,
      linkedTransactionId: map['linked_transaction_id'] as int?,
      parentTransactionId: map['parent_transaction_id'] as int?,
      dueDate: map['due_date'] != null
          ? DateTime.parse(map['due_date'] as String)
          : null,
      interestRate: (map['interest_rate'] as num?)?.toDouble(),
      interestType: InterestType.fromDb(map['interest_type'] as String?),
      repaymentFrequency:
          RepaymentFrequency.fromDb(map['repayment_frequency'] as String?),
      totalInstallments: map['total_installments'] as int?,
      emiAmount: (map['emi_amount'] as num?)?.toDouble(),
      loanId: map['loan_id'] as int?,
      dedupeHash: map['dedupe_hash'] as String?,
      notes: map['notes'] as String?,
      tags: (map['tags'] as String?)
          ?.split(',')
          .where((t) => t.isNotEmpty)
          .toList(),
      reminderSentAt: map['reminder_sent_at'] != null
          ? DateTime.parse(map['reminder_sent_at'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  /// Whether this transaction was auto-created by a Loan contract.
  bool get isLoanLinked => loanId != null;

  @override
  List<Object?> get props => [id, amount, date, type, category, dedupeHash];
}
