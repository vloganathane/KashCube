import 'package:equatable/equatable.dart';

/// The type of party relationship.
enum PartyType {
  customer,
  vendor,
  lender,
  borrower;

  String get label {
    switch (this) {
      case PartyType.customer:
        return 'Customer';
      case PartyType.vendor:
        return 'Vendor';
      case PartyType.lender:
        return 'Lender';
      case PartyType.borrower:
        return 'Borrower';
    }
  }
}

/// A party (customer, vendor, lender) involved in transactions.
class Party extends Equatable {
  const Party({
    this.id,
    required this.name,
    this.phoneNumber,
    this.email,
    this.gstin,
    this.address,
    required this.partyType,
    this.totalTransactions = 0,
    this.totalTransactionAmount = 0,
    this.totalCreditGiven = 0,
    this.totalCreditReceived = 0,
    this.notes,
    this.tags,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final String name;
  final String? phoneNumber;
  final String? email;
  /// GST Identification Number — stored locally, never validated via network.
  final String? gstin;
  /// Physical address — stored locally, never transmitted.
  final String? address;
  final PartyType partyType;
  final int totalTransactions;
  final double totalTransactionAmount;
  final double totalCreditGiven;
  final double totalCreditReceived;
  final String? notes;
  final List<String>? tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Net credit balance for this party (given - received).
  double get netCredit => totalCreditGiven - totalCreditReceived;

  Party copyWith({
    int? id,
    String? name,
    String? phoneNumber,
    String? email,
    String? gstin,
    String? address,
    PartyType? partyType,
    int? totalTransactions,
    double? totalTransactionAmount,
    double? totalCreditGiven,
    double? totalCreditReceived,
    String? notes,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      gstin: gstin ?? this.gstin,
      address: address ?? this.address,
      partyType: partyType ?? this.partyType,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      totalTransactionAmount: totalTransactionAmount ?? this.totalTransactionAmount,
      totalCreditGiven: totalCreditGiven ?? this.totalCreditGiven,
      totalCreditReceived: totalCreditReceived ?? this.totalCreditReceived,
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
      'name': name,
      'phone_number': phoneNumber,
      'email': email,
      'gstin': gstin,
      'address': address,
      'party_type': partyType.name,
      'total_transactions': totalTransactions,
      'total_transaction_amount': totalTransactionAmount,
      'total_credit_given': totalCreditGiven,
      'total_credit_received': totalCreditReceived,
      'notes': notes,
      'tags': tags?.join(','),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id'] as int?,
      name: map['name'] as String,
      phoneNumber: map['phone_number'] as String?,
      email: map['email'] as String?,
      gstin: map['gstin'] as String?,
      address: map['address'] as String?,
      partyType: PartyType.values.firstWhere(
        (e) => e.name == (map['party_type'] as String? ?? 'customer'),
        orElse: () => PartyType.customer,
      ),
      totalTransactions: (map['total_transactions'] as int?) ?? 0,
      totalTransactionAmount: (map['total_transaction_amount'] as num? ?? 0).toDouble(),
      totalCreditGiven: (map['total_credit_given'] as num? ?? 0).toDouble(),
      totalCreditReceived: (map['total_credit_received'] as num? ?? 0).toDouble(),
      notes: map['notes'] as String?,
      tags: (map['tags'] as String?)?.split(',').where((t) => t.isNotEmpty).toList(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [id, name, partyType];
}
