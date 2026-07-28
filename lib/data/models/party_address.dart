import 'package:equatable/equatable.dart';

/// A named delivery / billing address linked to a [Party].
///
/// A party can have multiple addresses: Head Office, Warehouse, Site, etc.
/// One address per party can be marked as the default, which is auto-populated
/// when that customer is selected on a Delivery Challan or Invoice form.
class PartyAddress extends Equatable {
  const PartyAddress({
    this.id,
    required this.partyId,
    required this.label,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.country = 'India',
    this.gstin,
    this.isDefault = false,
    required this.createdAt,
  });

  final int? id;

  /// FK → parties(id)
  final int partyId;

  /// Human-readable label, e.g. "Head Office", "Warehouse", "Mumbai Branch"
  final String label;

  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? country;

  /// Optional location-specific GSTIN (common for multi-location businesses)
  final String? gstin;

  final bool isDefault;
  final DateTime createdAt;

  /// One-line summary for display in pickers and chips.
  String get displayLine {
    final parts = <String>[
      if (address != null && address!.isNotEmpty) address!,
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (pincode != null && pincode!.isNotEmpty) pincode!,
    ];
    return parts.isEmpty ? label : parts.join(', ');
  }

  PartyAddress copyWith({
    int? id,
    int? partyId,
    String? label,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? country,
    String? gstin,
    bool? isDefault,
    DateTime? createdAt,
  }) => PartyAddress(
    id: id ?? this.id,
    partyId: partyId ?? this.partyId,
    label: label ?? this.label,
    address: address ?? this.address,
    city: city ?? this.city,
    state: state ?? this.state,
    pincode: pincode ?? this.pincode,
    country: country ?? this.country,
    gstin: gstin ?? this.gstin,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'party_id': partyId,
    'label': label,
    'address': address,
    'city': city,
    'state': state,
    'pincode': pincode,
    'country': country,
    'gstin': gstin,
    'is_default': isDefault ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory PartyAddress.fromMap(Map<String, dynamic> map) => PartyAddress(
    id: map['id'] as int?,
    partyId: map['party_id'] as int,
    label: (map['label'] as String?) ?? 'Address',
    address: map['address'] as String?,
    city: map['city'] as String?,
    state: map['state'] as String?,
    pincode: map['pincode'] as String?,
    country: (map['country'] as String?) ?? 'India',
    gstin: map['gstin'] as String?,
    isDefault: (map['is_default'] as int?) == 1,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  @override
  List<Object?> get props => [
    id,
    partyId,
    label,
    address,
    city,
    state,
    pincode,
    gstin,
    isDefault,
  ];
}
