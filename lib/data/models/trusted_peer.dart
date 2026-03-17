/// A paired device that this KashCube install trusts for P2P LAN sync.
///
/// The [sharedSecretEnc] field stores the HKDF-derived shared secret
/// encrypted with this device's Ed25519 private key (AES-256-GCM, stored
/// as base64). The raw secret is never persisted in plaintext.
class TrustedPeer {
  const TrustedPeer({
    this.id,
    required this.peerIdentityId,
    this.peerName,
    this.businessId,
    required this.sharedSecretEnc,
    required this.pairedAt,
    this.lastSeenAt,
    this.lastSyncedAt,
    this.isActive = true,
  });

  final int? id;

  /// Permanent identity UUID of the remote device (from its `my_identity` row).
  final String peerIdentityId;

  /// Human-readable device name shown in the UI.
  final String? peerName;

  /// Business context the peer belongs to (optional; null = personal scope).
  final String? businessId;

  /// AES-256-GCM encrypted shared secret (base64). Decrypted at runtime only.
  final String sharedSecretEnc;

  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? lastSyncedAt;
  final bool isActive;

  factory TrustedPeer.fromMap(Map<String, dynamic> map) => TrustedPeer(
        id:               map['id'] as int?,
        peerIdentityId:   map['peer_identity_id'] as String,
        peerName:         map['peer_name'] as String?,
        businessId:       map['business_id'] as String?,
        sharedSecretEnc:  map['shared_secret_enc'] as String,
        pairedAt:         DateTime.parse(map['paired_at'] as String),
        lastSeenAt:       map['last_seen_at'] == null
            ? null
            : DateTime.parse(map['last_seen_at'] as String),
        lastSyncedAt:     map['last_synced_at'] == null
            ? null
            : DateTime.parse(map['last_synced_at'] as String),
        isActive:         (map['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'peer_identity_id':  peerIdentityId,
        if (peerName != null) 'peer_name': peerName,
        if (businessId != null) 'business_id': businessId,
        'shared_secret_enc': sharedSecretEnc,
        'paired_at':         pairedAt.toIso8601String(),
        if (lastSeenAt != null) 'last_seen_at': lastSeenAt!.toIso8601String(),
        if (lastSyncedAt != null)
          'last_synced_at': lastSyncedAt!.toIso8601String(),
        'is_active': isActive ? 1 : 0,
      };

  TrustedPeer copyWith({
    String? peerName,
    DateTime? lastSeenAt,
    DateTime? lastSyncedAt,
    bool? isActive,
  }) =>
      TrustedPeer(
        id:              id,
        peerIdentityId:  peerIdentityId,
        peerName:        peerName ?? this.peerName,
        businessId:      businessId,
        sharedSecretEnc: sharedSecretEnc,
        pairedAt:        pairedAt,
        lastSeenAt:      lastSeenAt ?? this.lastSeenAt,
        lastSyncedAt:    lastSyncedAt ?? this.lastSyncedAt,
        isActive:        isActive ?? this.isActive,
      );

  @override
  String toString() =>
      'TrustedPeer($peerIdentityId, name=$peerName, active=$isActive)';
}
