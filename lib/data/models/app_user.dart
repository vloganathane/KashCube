import 'package:equatable/equatable.dart';

/// Role presets for app users.
/// Owner is NOT stored in app_users — owner = activeAppUserProvider is null.
enum AppUserRole {
  manager,
  cashier,
  auditor,
  custom;

  String get dbValue => name;
  String get label => switch (this) {
        AppUserRole.manager => 'Manager',
        AppUserRole.cashier => 'Cashier',
        AppUserRole.auditor => 'Auditor',
        AppUserRole.custom => 'Custom',
      };

  static AppUserRole fromDb(String value) =>
      AppUserRole.values.firstWhere((r) => r.dbValue == value,
          orElse: () => AppUserRole.custom);
}

class AppUser extends Equatable {
  const AppUser({
    this.id,
    required this.syncId,
    required this.displayName,
    this.pinHash,
    this.role = AppUserRole.custom,
    this.linkedPartyId,
    this.isActive = true,
    this.defaultDeviceId,
    this.lastLoginAt,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String syncId;
  final String displayName;
  final String? pinHash;
  final AppUserRole role;
  final int? linkedPartyId;
  final bool isActive;
  final String? defaultDeviceId;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Initials for avatar display (up to 2 chars)
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  AppUser copyWith({
    int? id,
    String? syncId,
    String? displayName,
    String? pinHash,
    AppUserRole? role,
    int? linkedPartyId,
    bool? isActive,
    String? defaultDeviceId,
    DateTime? lastLoginAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      AppUser(
        id: id ?? this.id,
        syncId: syncId ?? this.syncId,
        displayName: displayName ?? this.displayName,
        pinHash: pinHash ?? this.pinHash,
        role: role ?? this.role,
        linkedPartyId: linkedPartyId ?? this.linkedPartyId,
        isActive: isActive ?? this.isActive,
        defaultDeviceId: defaultDeviceId ?? this.defaultDeviceId,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as int?,
        syncId: map['sync_id'] as String,
        displayName: map['display_name'] as String,
        pinHash: map['pin_hash'] as String?,
        role: AppUserRole.fromDb(map['role'] as String? ?? 'custom'),
        linkedPartyId: map['linked_party_id'] as int?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        defaultDeviceId: map['default_device_id'] as String?,
        lastLoginAt: map['last_login_at'] != null
            ? DateTime.parse(map['last_login_at'] as String)
            : null,
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : null,
        updatedAt: map['updated_at'] != null
            ? DateTime.parse(map['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (syncId.isNotEmpty) 'sync_id': syncId, // omitted for new inserts → DB DEFAULT generates UUID
        'display_name': displayName,
        if (pinHash != null) 'pin_hash': pinHash,
        'role': role.dbValue,
        if (linkedPartyId != null) 'linked_party_id': linkedPartyId,
        'is_active': isActive ? 1 : 0,
        if (defaultDeviceId != null) 'default_device_id': defaultDeviceId,
        if (lastLoginAt != null) 'last_login_at': lastLoginAt!.toIso8601String(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        id, syncId, displayName, pinHash, role, linkedPartyId,
        isActive, defaultDeviceId, lastLoginAt,
      ];
}
