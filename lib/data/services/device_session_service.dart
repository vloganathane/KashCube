import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/device_session_token.dart';
import 'database_helper.dart';
import 'identity_service.dart';

/// Manages the secondary device's stored session credential (`device_session`
/// table, one row max).
///
/// Primary devices have no `device_session` row — all methods return early.
///
/// Usage:
/// ```dart
/// final session = await DeviceSessionService.instance.loadAndVerify(
///   DatabaseHelper.instance, IdentityService.instance,
/// );
/// ```
class DeviceSessionService {
  DeviceSessionService._();
  static final DeviceSessionService instance = DeviceSessionService._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Reads the `device_session` table and verifies the primary's Ed25519
  /// signature over the token payload.
  ///
  /// Returns `null` when:
  /// - There is no row (this is the primary device).
  /// - The signature is invalid (token was tampered with).
  Future<DeviceSession?> loadAndVerify(
    DatabaseHelper dbHelper,
    IdentityService identity,
  ) async {
    final rows = await dbHelper.withDatabase(
      (db) => db.query('device_session', limit: 1),
    );
    if (rows.isEmpty) return null;

    final session = DeviceSession.fromMap(
      Map<String, dynamic>.from(rows.first),
    );

    // Verify the primary's Ed25519 signature on the token payload.
    final valid = await identity.verify(
      message:         utf8.encode(session.token.payload),
      sigBase64:       session.token.signatureBase64,
      publicKeyBase64: session.token.primaryPublicKeyBase64,
    );
    if (!valid) {
      debugPrint('DeviceSessionService: token signature invalid — not loading session');
      return null;
    }

    return session;
  }

  /// Checks the offline grace period and, if exceeded, sets
  /// `is_read_only_forced = 1` in the DB.
  ///
  /// Returns an updated [DeviceSession] with [DeviceSession.isReadOnlyForced]
  /// = `true` when the grace period has been exceeded.
  Future<DeviceSession> enforceGrace(
    DeviceSession session,
    DatabaseHelper dbHelper,
  ) async {
    if (session.isReadOnlyForced) return session;

    final lastSync = session.lastSyncAt;
    if (lastSync == null) return session;

    final daysSince = DateTime.now().difference(lastSync).inDays;
    if (daysSince >= session.token.offlineGraceDays) {
      await dbHelper.withDatabase(
        (db) => db.update('device_session', {'is_read_only_forced': 1}),
      );
      debugPrint(
        'DeviceSessionService: grace period exceeded ($daysSince days) — read-only forced',
      );
      return DeviceSession(
        thisDeviceId:     session.thisDeviceId,
        primaryDeviceId:  session.primaryDeviceId,
        token:            session.token,
        lastSyncAt:       session.lastSyncAt,
        isReadOnlyForced: true,
      );
    }

    return session;
  }

  /// Deletes the `device_session` row.  Called when the primary revokes this
  /// device during a sync cycle.
  Future<void> wipeSession(DatabaseHelper dbHelper) async {
    await dbHelper.withDatabase((db) => db.delete('device_session'));
    debugPrint('DeviceSessionService: session wiped (device revoked)');
  }
}
