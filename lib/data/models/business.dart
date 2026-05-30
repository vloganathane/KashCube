import 'dart:convert';

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
    this.country,
    this.dialCode,
    this.phone,
    this.email,
    this.phones,
    this.gstNo,
    this.logoPath,
    this.logoMediaId,
    this.isActive = false,
    this.ownerName,
    this.website,
    this.whatsapp,
    this.linkedin,
    this.instagram,
    this.upiId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  /// Country name (e.g. 'India', 'United Arab Emirates'). Null means India.
  final String? country;
  /// Dial code digits without '+' (e.g. '91', '971'). Null means '91' (India).
  final String? dialCode;
  final String? phone;
  /// Additional phone numbers for the business. First element is primary.
  final List<String>? phones;
  final String? email;
  final String? gstNo;

  /// Absolute path to a locally stored logo image.
  final String? logoPath;

  /// Stable media identifier shared across devices/web for business logo.
  final String? logoMediaId;

  /// Whether this is the currently active business for invoicing.
  final bool isActive;

  /// Owner/contact name for this business profile.
  final String? ownerName;
  final String? website;
  final String? whatsapp;
  final String? linkedin;
  final String? instagram;

  /// UPI Virtual Payment Address (VPA) – used to generate a payment QR code
  /// on invoices. Example: 'yourname@upi'. Stored locally, never transmitted.
  final String? upiId;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// One-line address for display on invoices.
  String get formattedAddress {
    final parts = <String>[
      if (address != null && address!.isNotEmpty) address!,
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (pincode != null && pincode!.isNotEmpty) pincode!,
      if (country != null && country!.isNotEmpty && country != 'India') country!,
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
    String? country,
    String? dialCode,
    String? phone,
    String? email,
    String? gstNo,
    String? logoPath,
    String? logoMediaId,
    bool? isActive,
    String? ownerName,
    String? website,
    String? whatsapp,
    String? linkedin,
    String? instagram,
    String? upiId,
    List<String>? phones,
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
        country: country ?? this.country,
        dialCode: dialCode ?? this.dialCode,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        gstNo: gstNo ?? this.gstNo,
        logoPath: logoPath ?? this.logoPath,
        logoMediaId: logoMediaId ?? this.logoMediaId,
        isActive: isActive ?? this.isActive,
        ownerName: ownerName ?? this.ownerName,
        website: website ?? this.website,
        whatsapp: whatsapp ?? this.whatsapp,
        linkedin: linkedin ?? this.linkedin,
        instagram: instagram ?? this.instagram,
        upiId: upiId ?? this.upiId,
        phones: phones ?? this.phones,
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
        'country': country,
        'dial_code': dialCode,
        'phone': phone,
        'phones_json': phones == null ? null : jsonEncode(phones),
        'email': email,
        'gst_no': gstNo,
        'logo_path': logoPath,
        'logo_media_id': logoMediaId,
        'is_active': isActive ? 1 : 0,
        'owner_name': ownerName,
        'website': website,
        'whatsapp': whatsapp,
        'linkedin': linkedin,
        'instagram': instagram,
        'upi_id': upiId,
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
        country: map['country'] as String?,
        dialCode: map['dial_code'] as String?,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        gstNo: map['gst_no'] as String?,
        logoPath: map['logo_path'] as String?,
        logoMediaId: map['logo_media_id'] as String?,
        isActive: (map['is_active'] as int? ?? 0) == 1,
        ownerName: map['owner_name'] as String?,
        website: map['website'] as String?,
        whatsapp: map['whatsapp'] as String?,
        linkedin: map['linkedin'] as String?,
        instagram: map['instagram'] as String?,
        upiId: map['upi_id'] as String?,
        phones: (() {
          try {
            final raw = map['phones_json'] as String?;
            if (raw != null && raw.isNotEmpty) {
              final decoded = jsonDecode(raw);
              if (decoded is List) return decoded.cast<String>();
            }
          } catch (_) {}
          final single = map['phone'] as String?;
          return single == null ? null : <String>[single];
        })(),
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props => [id, name, gstNo, phone, phones, isActive, upiId, logoMediaId];
}
