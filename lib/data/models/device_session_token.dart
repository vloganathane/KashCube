import 'dart:convert';

import 'package:equatable/equatable.dart';

/// A signed session token issued by the primary device to a secondary.
/// Stored in the `linked_business_sessions` table on the secondary.
class DeviceSessionToken extends Equatable {
  const DeviceSessionToken({
    required this.payload,
    required this.signatureBase64,
    required this.primaryPublicKeyBase64,
  });

  final String payload;             // raw JSON string (signed)
  final String signatureBase64;     // base64 of 64-byte Ed25519 signature
  final String primaryPublicKeyBase64; // base64 of primary's 32-byte public key

  /// Decoded payload fields.
  Map<String, dynamic> get decodedPayload =>
      jsonDecode(payload) as Map<String, dynamic>;

  String get deviceId => decodedPayload['device_id'] as String;
  String get permissionScope => decodedPayload['permission_scope'] as String;
  String get businessScope => decodedPayload['business_scope'] as String;
  String get issuedAt => decodedPayload['issued_at'] as String;
  int get offlineGraceDays => decodedPayload['offline_grace_days'] as int? ?? 7;
  String get preset => decodedPayload['preset'] as String? ?? 'owner_mirror';

  /// Feature map embedded by the primary at pairing time.
  /// Keys are feature names (e.g. 'lan_sync'); value is a map with
  /// `enabled` (bool) and `limit` (int) from the primary's plan_features table.
  /// Returns `null` for tokens issued before D3 (v64).
  Map<String, dynamic>? get planFeatures =>
      decodedPayload['plan_features'] as Map<String, dynamic>?;

  factory DeviceSessionToken.fromMap(Map<String, dynamic> map) =>
      DeviceSessionToken(
        payload:                 map['token_payload'] as String,
        signatureBase64:         map['token_signature'] as String,
        primaryPublicKeyBase64:  map['primary_public_key'] as String,
      );

  Map<String, dynamic> toMap() => {
        'token_payload':      payload,
        'token_signature':    signatureBase64,
        'primary_public_key': primaryPublicKeyBase64,
      };

  @override
  List<Object?> get props => [payload, signatureBase64];
}

/// A row from `linked_business_sessions` on a secondary device.
class DeviceSession {
  const DeviceSession({
    required this.sessionId,
    required this.primaryIdentityId,
    required this.token,
    this.businessName = 'Linked Business',
    this.lastSyncAt,
    this.isReadOnlyForced = false,
  });

  /// The local session UUID (`session_id`).
  final String sessionId;

  /// The primary's identity UUID (`primary_identity_id`).
  final String primaryIdentityId;

  final DeviceSessionToken token;
  final String businessName;
  final DateTime? lastSyncAt;
  final bool isReadOnlyForced;

  factory DeviceSession.fromMap(Map<String, dynamic> map) => DeviceSession(
        sessionId:        map['session_id'] as String? ?? '',
        primaryIdentityId: map['primary_identity_id'] as String? ??
            (map['primary_device_id'] as String? ?? ''),
        token:            DeviceSessionToken.fromMap(map),
        businessName:     map['business_name'] as String? ?? 'Linked Business',
        lastSyncAt:       map['last_sync_at'] != null
            ? DateTime.parse(map['last_sync_at'] as String)
            : null,
        isReadOnlyForced: (map['is_read_only_forced'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        'session_id':           sessionId,
        'primary_identity_id':  primaryIdentityId,
        'business_name':        businessName,
        ...token.toMap(),
        if (lastSyncAt != null) 'last_sync_at': lastSyncAt!.toIso8601String(),
        'is_read_only_forced': isReadOnlyForced ? 1 : 0,
        'issued_at':           DateTime.now().toIso8601String(),
      };
}
