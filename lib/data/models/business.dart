import 'package:equatable/equatable.dart';

/// A business profile used for invoicing.
/// All data is stored locally — never transmitted.
class Business extends Equatable {
  const Business({
    this.id,
    required this.name,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.phone,
    this.email,
    this.gstNo,
    this.logoPath,
    this.isActive = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? phone;
  final String? email;
  final String? gstNo;

  /// Absolute path to a locally stored logo image.
  final String? logoPath;

  /// Whether this is the currently active business for invoicing.
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// One-line address for display on invoices.
  String get formattedAddress {
    final parts = <String>[
      if (address != null && address!.isNotEmpty) address!,
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (pincode != null && pincode!.isNotEmpty) pincode!,
    ];
    return parts.join(', ');
  }

  Business copyWith({
    int? id,
    String? name,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? phone,
    String? email,
    String? gstNo,
    String? logoPath,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Business(
        id: id ?? this.id,
        name: name ?? this.name,
        address: address ?? this.address,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        gstNo: gstNo ?? this.gstNo,
        logoPath: logoPath ?? this.logoPath,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'phone': phone,
        'email': email,
        'gst_no': gstNo,
        'logo_path': logoPath,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Business.fromMap(Map<String, dynamic> map) => Business(
        id: map['id'] as int?,
        name: map['name'] as String,
        address: map['address'] as String?,
        city: map['city'] as String?,
        state: map['state'] as String?,
        pincode: map['pincode'] as String?,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        gstNo: map['gst_no'] as String?,
        logoPath: map['logo_path'] as String?,
        isActive: (map['is_active'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props => [id, name, gstNo, phone, isActive];
}
