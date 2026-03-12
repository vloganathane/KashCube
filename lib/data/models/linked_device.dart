import 'package:equatable/equatable.dart';

/// Permission preset applied to a linked (secondary) device.
enum DevicePreset {
  ownerMirror('owner_mirror', 'Owner Mirror'),
  manager('manager', 'Manager'),
  cashier('cashier', 'Cashier'),
  auditor('auditor', 'Auditor'),
  custom('custom', 'Custom');

  const DevicePreset(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DevicePreset fromDb(String v) =>
      DevicePreset.values.firstWhere((e) => e.dbValue == v,
          orElse: () => DevicePreset.custom);
}

/// A secondary device that has been paired with this primary.
/// Stored in the `linked_devices` table on the primary only.
class LinkedDevice extends Equatable {
  const LinkedDevice({
    this.id,
    required this.syncId,
    required this.deviceId,
    required this.deviceName,
    this.deviceType,
    this.deviceOs,
    required this.secondaryPublicKey,
    this.userId,
    this.linkedPartyId,
    required this.permissionScope,
    required this.businessScope,
    this.offlineGraceDays = 7,
    this.lastSyncAt,
    this.revokedAt,
    this.createdAt,
    this.preset = DevicePreset.ownerMirror,
    this.secondaryIdentityId,
    this.secondaryDisplayName,
  });

  final int? id;
  final String syncId;
  final String deviceId;       // UUID generated on secondary at install
  final String deviceName;     // e.g. "Ravi's Tablet"
  final String? deviceType;    // 'phone' | 'tablet'
  final String? deviceOs;      // 'android' | 'ios'
  final String secondaryPublicKey; // base64 Ed25519 public key
  final int? userId;           // FK app_users — null = owner mirror
  final int? linkedPartyId;    // FK parties for HRMS linkage
  final String permissionScope; // JSON blob
  final String businessScope;  // JSON array of business IDs
  final int offlineGraceDays;
  final DateTime? lastSyncAt;
  final DateTime? revokedAt;
  final DateTime? createdAt;
  final DevicePreset preset;
  /// Permanent identity UUID of the secondary device (from `my_identity`).
  /// Populated during D3 identity-first pairing; null for older pairings.
  final String? secondaryIdentityId;
  /// Human-readable display name of the secondary's identity.
  /// e.g. "Ravi Kumar" — shown in LinkedDevicesScreen instead of device name.
  final String? secondaryDisplayName;

  bool get isActive => revokedAt == null;
  bool get isOwnerMirror => preset == DevicePreset.ownerMirror;

  factory LinkedDevice.fromMap(Map<String, dynamic> map) => LinkedDevice(
        id:                 map['id'] as int?,
        syncId:             map['sync_id'] as String? ?? '',
        deviceId:           map['device_id'] as String,
        deviceName:         map['device_name'] as String,
        deviceType:         map['device_type'] as String?,
        deviceOs:           map['device_os'] as String?,
        secondaryPublicKey: map['secondary_public_key'] as String,
        userId:             map['user_id'] as int?,
        linkedPartyId:      map['linked_party_id'] as int?,
        permissionScope:    map['permission_scope'] as String? ?? '{}',
        businessScope:      map['business_scope'] as String? ?? '[]',
        offlineGraceDays:   map['offline_grace_days'] as int? ?? 7,
        lastSyncAt:         map['last_sync_at'] != null
            ? DateTime.parse(map['last_sync_at'] as String)
            : null,
        revokedAt:          map['revoked_at'] != null
            ? DateTime.parse(map['revoked_at'] as String)
            : null,
        createdAt:          map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : null,
        preset:             DevicePreset.fromDb(
            map['permission_preset'] as String? ?? 'owner_mirror'),
        secondaryIdentityId:   map['secondary_identity_id'] as String?,
        secondaryDisplayName:  map['secondary_display_name'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'device_id': deviceId,
        'device_name': deviceName,
        if (deviceType != null) 'device_type': deviceType,
        if (deviceOs != null) 'device_os': deviceOs,
        'secondary_public_key': secondaryPublicKey,
        if (userId != null) 'user_id': userId,
        if (linkedPartyId != null) 'linked_party_id': linkedPartyId,
        'permission_scope': permissionScope,
        'business_scope': businessScope,
        'offline_grace_days': offlineGraceDays,
        'permission_preset': preset.dbValue,
        if (lastSyncAt != null) 'last_sync_at': lastSyncAt!.toIso8601String(),
        if (revokedAt != null) 'revoked_at': revokedAt!.toIso8601String(),
        if (secondaryIdentityId != null) 'secondary_identity_id': secondaryIdentityId,
        if (secondaryDisplayName != null) 'secondary_display_name': secondaryDisplayName,
      };

  LinkedDevice copyWith({
    int? id,
    String? syncId,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? deviceOs,
    String? secondaryPublicKey,
    int? userId,
    int? linkedPartyId,
    String? permissionScope,
    String? businessScope,
    int? offlineGraceDays,
    DateTime? lastSyncAt,
    DateTime? revokedAt,
    DateTime? createdAt,
    DevicePreset? preset,
    String? secondaryIdentityId,
    String? secondaryDisplayName,
  }) =>
      LinkedDevice(
        id:                 id              ?? this.id,
        syncId:             syncId          ?? this.syncId,
        deviceId:           deviceId        ?? this.deviceId,
        deviceName:         deviceName      ?? this.deviceName,
        deviceType:         deviceType      ?? this.deviceType,
        deviceOs:           deviceOs        ?? this.deviceOs,
        secondaryPublicKey: secondaryPublicKey ?? this.secondaryPublicKey,
        userId:             userId          ?? this.userId,
        linkedPartyId:      linkedPartyId   ?? this.linkedPartyId,
        permissionScope:    permissionScope ?? this.permissionScope,
        businessScope:      businessScope   ?? this.businessScope,
        offlineGraceDays:   offlineGraceDays ?? this.offlineGraceDays,
        lastSyncAt:         lastSyncAt      ?? this.lastSyncAt,
        revokedAt:          revokedAt       ?? this.revokedAt,
        createdAt:          createdAt       ?? this.createdAt,
        preset:             preset          ?? this.preset,
        secondaryIdentityId:  secondaryIdentityId  ?? this.secondaryIdentityId,
        secondaryDisplayName: secondaryDisplayName ?? this.secondaryDisplayName,
      );

  @override
  List<Object?> get props => [
        id, deviceId, deviceName, secondaryPublicKey,
        permissionScope, businessScope, revokedAt,
        secondaryIdentityId, secondaryDisplayName,
      ];
}
