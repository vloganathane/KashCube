import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/device_session_token.dart';
import 'database_helper.dart';
import 'identity_service.dart';

/// Manages the secondary device's stored session credential
/// (`linked_business_sessions` table, one active row max).
///
/// Primary devices have no row — all methods return early.
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

  static const String _kTable = 'linked_business_sessions';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Reads the first active `linked_business_sessions` row and verifies the
  /// primary's Ed25519 signature over the token payload.
  ///
  /// Returns `null` when:
  /// - There is no active row (this is the primary device or has no session).
  /// - The signature is invalid (token was tampered with).
  Future<DeviceSession?> loadAndVerify(
    DatabaseHelper dbHelper,
    IdentityService identity,
  ) async {
    final rows = await dbHelper.withDatabase(
      (db) => db.query(
        _kTable,
        where: 'unlinked_at IS NULL',
        limit: 1,
      ),
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
        (db) => db.update(
          _kTable,
          {'is_read_only_forced': 1},
          where: 'session_id = ?',
          whereArgs: [session.sessionId],
        ),
      );
      debugPrint(
        'DeviceSessionService: grace period exceeded ($daysSince days) — read-only forced',
      );
      return DeviceSession(
        sessionId:        session.sessionId,
        primaryIdentityId: session.primaryIdentityId,
        token:            session.token,
        businessName:     session.businessName,
        lastSyncAt:       session.lastSyncAt,
        isReadOnlyForced: true,
      );
    }

    return session;
  }

  /// Marks all active sessions as unlinked.  Called when the primary revokes
  /// this device during a sync cycle.
  Future<void> wipeSession(DatabaseHelper dbHelper) async {
    await dbHelper.withDatabase(
      (db) => db.update(
        _kTable,
        {'unlinked_at': DateTime.now().toIso8601String()},
        where: 'unlinked_at IS NULL',
      ),
    );
    debugPrint('DeviceSessionService: session wiped (device revoked)');
  }
}
