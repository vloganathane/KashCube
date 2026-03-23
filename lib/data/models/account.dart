import 'package:equatable/equatable.dart';

/// Account type enum.
enum AccountType {
  savings,
  current,
  cash,
  creditCard,
  debitCard,
  upiWallet,
  paymentWallet;

  String get label {
    switch (this) {
      case AccountType.savings:
        return 'Savings';
      case AccountType.current:
        return 'Current';
      case AccountType.cash:
        return 'Cash';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.debitCard:
        return 'Debit Card';
      case AccountType.upiWallet:
        return 'UPI Wallet';
      case AccountType.paymentWallet:
        return 'Payment Wallet';
    }
  }

  String get dbValue => name;

  static AccountType fromDb(String value) {
    return AccountType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AccountType.savings,
    );
  }
}

/// A payment account (bank account, card, wallet, or cash).
class Account extends Equatable {
  const Account({
    this.id,
    required this.accountType,
    required this.accountName,
    this.bankName,
    this.accountNumberLast4,
    this.currentBalance,
    this.creditLimit,
    this.isActive = true,
    this.isPrimary = false,
    this.smsSenders,
    this.notes,
    this.color,
    this.icon,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final AccountType accountType;
  final String accountName;
  final String? bankName;
  final String? accountNumberLast4;
  final double? currentBalance;
  /// For credit card accounts: the total approved credit limit.
  final double? creditLimit;
  final bool isActive;
  final bool isPrimary;
  final List<String>? smsSenders;
  final String? notes;
  final String? color;
  final String? icon;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  Account copyWith({
    int? id,
    AccountType? accountType,
    String? accountName,
    String? bankName,
    String? accountNumberLast4,
    double? currentBalance,
    double? creditLimit,
    bool? isActive,
    bool? isPrimary,
    List<String>? smsSenders,
    String? notes,
    String? color,
    String? icon,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Account(
      id: id ?? this.id,
      accountType: accountType ?? this.accountType,
      accountName: accountName ?? this.accountName,
      bankName: bankName ?? this.bankName,
      accountNumberLast4: accountNumberLast4 ?? this.accountNumberLast4,
      currentBalance: currentBalance ?? this.currentBalance,
      creditLimit: creditLimit ?? this.creditLimit,
      isActive: isActive ?? this.isActive,
      isPrimary: isPrimary ?? this.isPrimary,
      smsSenders: smsSenders ?? this.smsSenders,
      notes: notes ?? this.notes,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'account_type': accountType.dbValue,
      'account_name': accountName,
      'bank_name': bankName,
      'account_number_last4': accountNumberLast4,
      'current_balance': currentBalance,
      'credit_limit': creditLimit,
      'is_active': isActive ? 1 : 0,
      'is_primary': isPrimary ? 1 : 0,
      'sms_senders': smsSenders?.join(','),
      'notes': notes,
      'color': color,
      'icon': icon,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      accountType: AccountType.fromDb(map['account_type'] as String),
      accountName: map['account_name'] as String,
      bankName: map['bank_name'] as String?,
      accountNumberLast4: map['account_number_last4'] as String?,
      currentBalance: (map['current_balance'] as num?)?.toDouble(),
      creditLimit: (map['credit_limit'] as num?)?.toDouble(),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isPrimary: (map['is_primary'] as int? ?? 0) == 1,
      smsSenders: (map['sms_senders'] as String?)?.split(',').where((s) => s.isNotEmpty).toList(),
      notes: map['notes'] as String?,
      color: map['color'] as String?,
      icon: map['icon'] as String?,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [id, accountName, accountType];
}
