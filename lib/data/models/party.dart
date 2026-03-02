import 'package:equatable/equatable.dart';

/// The type of party relationship.
enum PartyType {
  personal,
  customer,
  vendor,
  lender,
  borrower;

  String get label {
    switch (this) {
      case PartyType.personal:
        return 'Personal';
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
    this.city,
    this.state,
    this.pincode,
    required this.partyType,
    this.partyContext = 'personal',
    this.totalTransactions = 0,
    this.totalTransactionAmount = 0,
    this.totalCreditGiven = 0,
    this.totalCreditReceived = 0,
    this.notes,
    this.tags,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.businessCardImagePath,
    this.website,
    this.whatsapp,
    this.linkedin,
    this.instagram,
  });

  final int? id;
  final String name;
  final String? phoneNumber;
  final String? email;
  /// GST Identification Number — stored locally, never validated via network.
  final String? gstin;
  /// Physical address (street) — stored locally, never transmitted.
  final String? address;
  /// City — stored locally, never transmitted.
  final String? city;
  /// State — stored locally, never transmitted.
  final String? state;
  /// Pincode — stored locally, never transmitted.
  final String? pincode;
  final PartyType partyType;

  /// Whether this is a personal or business relationship.
  /// Meaningful for `lender` and `borrower` types;
  /// implied for `vendor`/`customer` (business) and `personal` (personal).
  final String partyContext;

  final int totalTransactions;
  final double totalTransactionAmount;
  final double totalCreditGiven;
  final double totalCreditReceived;
  final String? notes;
  final List<String>? tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  /// Local file-system path to a business card photo/scan. Never transmitted.
  final String? businessCardImagePath;
  final String? website;
  final String? whatsapp;
  final String? linkedin;
  final String? instagram;

  /// Net credit balance for this party (given - received).
  double get netCredit => totalCreditGiven - totalCreditReceived;

  /// Formatted full address for display (street, city, state, pincode).
  String? get formattedAddress {
    final parts = <String>[
      if (address != null && address!.isNotEmpty) address!,
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (pincode != null && pincode!.isNotEmpty) pincode!,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  Party copyWith({
    int? id,
    String? name,
    String? phoneNumber,
    String? email,
    String? gstin,
    String? address,
    String? city,
    String? state,
    String? pincode,
    PartyType? partyType,
    String? partyContext,
    int? totalTransactions,
    double? totalTransactionAmount,
    double? totalCreditGiven,
    double? totalCreditReceived,
    String? notes,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? businessCardImagePath,
    String? website,
    String? whatsapp,
    String? linkedin,
    String? instagram,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      gstin: gstin ?? this.gstin,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      partyType: partyType ?? this.partyType,
      partyContext: partyContext ?? this.partyContext,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      totalTransactionAmount: totalTransactionAmount ?? this.totalTransactionAmount,
      totalCreditGiven: totalCreditGiven ?? this.totalCreditGiven,
      totalCreditReceived: totalCreditReceived ?? this.totalCreditReceived,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      businessCardImagePath: businessCardImagePath ?? this.businessCardImagePath,
      website: website ?? this.website,
      whatsapp: whatsapp ?? this.whatsapp,
      linkedin: linkedin ?? this.linkedin,
      instagram: instagram ?? this.instagram,
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
      'city': city,
      'state': state,
      'pincode': pincode,
      'party_type': partyType.name,
      'party_context': partyContext,
      'total_transactions': totalTransactions,
      'total_transaction_amount': totalTransactionAmount,
      'total_credit_given': totalCreditGiven,
      'total_credit_received': totalCreditReceived,
      'notes': notes,
      'tags': tags?.join(','),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'business_card_image_path': businessCardImagePath,
      'website': website,
      'whatsapp': whatsapp,
      'linkedin': linkedin,
      'instagram': instagram,
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
      city: map['city'] as String?,
      state: map['state'] as String?,
      pincode: map['pincode'] as String?,
      partyType: PartyType.values.firstWhere(
        (e) => e.name == (map['party_type'] as String? ?? 'personal'),
        orElse: () => PartyType.personal,
      ),
      partyContext: map['party_context'] as String? ?? 'personal',
      totalTransactions: (map['total_transactions'] as int?) ?? 0,
      totalTransactionAmount: (map['total_transaction_amount'] as num? ?? 0).toDouble(),
      totalCreditGiven: (map['total_credit_given'] as num? ?? 0).toDouble(),
      totalCreditReceived: (map['total_credit_received'] as num? ?? 0).toDouble(),
      notes: map['notes'] as String?,
      tags: (map['tags'] as String?)?.split(',').where((t) => t.isNotEmpty).toList(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
      businessCardImagePath: map['business_card_image_path'] as String?,
      website: map['website'] as String?,
      whatsapp: map['whatsapp'] as String?,
      linkedin: map['linkedin'] as String?,
      instagram: map['instagram'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, partyType, partyContext, businessCardImagePath];
}
