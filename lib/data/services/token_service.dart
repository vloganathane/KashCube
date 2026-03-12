import 'dart:convert';

import '../models/device_session_token.dart';
import '../models/linked_device.dart';
import 'identity_service.dart';

/// Issues and verifies signed session tokens.
///
/// A token payload is a JSON string containing:
///   device_id, permission_scope, business_scope, offline_grace_days,
///   preset, issued_at, plan_features (optional)
///
/// The payload is Ed25519-signed by the PRIMARY device.  The secondary stores
/// it in `device_session.token_payload` + `device_session.token_signature`.
class TokenService {
  const TokenService(this._identity);

  final IdentityService _identity;

  /// Issues a [DeviceSessionToken] for [device].
  /// Must be called on the PRIMARY device.
  ///
  /// [planFeatures] — optional map of feature → {enabled, limit} loaded from
  /// the primary's `plan_features` table.  When provided it is embedded in
  /// the signed payload so the secondary can gate features without a DB hit.
  Future<DeviceSessionToken> issue(
    LinkedDevice device, {
    Map<String, dynamic>? planFeatures,
  }) async {
    final payload = _buildPayload(device, planFeatures: planFeatures);
    final payloadBytes = utf8.encode(payload);
    final sig = await _identity.sign(payloadBytes);
    final pubKeyB64 = await _identity.publicKeyBase64;

    return DeviceSessionToken(
      payload:                 payload,
      signatureBase64:         base64.encode(sig.bytes),
      primaryPublicKeyBase64:  pubKeyB64,
    );
  }

  /// Verifies a [DeviceSessionToken] using the primary public key embedded in it.
  ///
  /// Returns `true` only when the signature is valid AND the grace period has
  /// not expired (i.e. the secondary device hasn't gone offline for too long).
  Future<bool> verify(DeviceSessionToken token) async {
    try {
      final payloadBytes = utf8.encode(token.payload);
      final valid = await _identity.verify(
        message:          payloadBytes,
        sigBase64:        token.signatureBase64,
        publicKeyBase64:  token.primaryPublicKeyBase64,
      );
      if (!valid) return false;

      // Grace-period check
      final issuedAt  = DateTime.parse(token.issuedAt);
      final expiresAt = issuedAt.add(Duration(days: token.offlineGraceDays));
      return DateTime.now().isBefore(expiresAt);
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _buildPayload(
    LinkedDevice device, {
    Map<String, dynamic>? planFeatures,
  }) {
    final map = <String, dynamic>{
      'device_id':          device.deviceId,
      'permission_scope':   device.permissionScope,
      'business_scope':     device.businessScope,
      'offline_grace_days': device.offlineGraceDays,
      'preset':             device.preset.dbValue,
      'issued_at':          DateTime.now().toIso8601String(),
      'plan_features': ?planFeatures,
    };
    return jsonEncode(map);
  }
}
