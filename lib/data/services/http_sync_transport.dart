import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/delta_row.dart';
import '../models/device_session_token.dart';
import 'database_helper.dart';
import 'identity_service.dart';
import 'sync_transport.dart';

// Conditional import: on web, use package:web XHR; on native, throws.
import 'http_client_stub.dart'
    if (dart.library.html) 'http_client_web.dart';

/// HTTP-based [SyncTransport] for the browser companion.
///
/// Replaces [WsSyncTransport] on web to avoid the WebSocket HijackException
/// issue that occurs when an async CORS middleware wraps the /ws upgrade.
///
/// Each method maps to a dedicated HTTP endpoint on the phone:
///   POST /api/v1/sync/pair   → pair request / response
///   POST /api/v1/sync/delta  → pull deltas from phone
///   POST /api/v1/sync/push   → push local deltas to phone
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    required this.identity,
    required this.dbHelper,
    required this.apiBase,
    required this.sessionToken,
  });

  final IdentityService identity;
  final DatabaseHelper  dbHelper;
  final String          apiBase;
  final String          sessionToken;

  // Tables the secondary can receive upserts for.
  static const List<String> _syncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
  ];

  // ── SyncTransport interface ───────────────────────────────────────────────

  @override
  Future<void> open(Uri endpoint) async {
    // HTTP is stateless — nothing to open. The apiBase / sessionToken were
    // passed in the constructor and are used directly per-request.
  }

  @override
  Future<void> close() async {
    // Nothing to close.
  }

  // ── Pairing ───────────────────────────────────────────────────────────────

  @override
  Future<DeviceSession> sendPairRequest({
    required String preset,
    required String deviceOs,
    required String deviceType,
    required String deviceName,
    String? secondaryIdentityId,
    String? secondaryDisplayName,
  }) async {
    final deviceId  = await identity.deviceId;
    final pubKeyB64 = await identity.publicKeyBase64;

    final body = <String, dynamic>{
      'type':        'pair_request',
      'device_id':   deviceId,
      'device_name': deviceName,
      'public_key':  pubKeyB64,
      'device_os':   deviceOs,
      'device_type': deviceType,
      'preset':      preset,
      if (secondaryIdentityId  != null) 'secondary_identity_id':   secondaryIdentityId,
      if (secondaryDisplayName != null) 'secondary_display_name':  secondaryDisplayName,
    };

    final resp = await httpPost(
      '$apiBase/sync/pair',
      body,
      sessionToken: sessionToken,
    );

    if (resp['type'] != 'pair_response') {
      throw SyncException('Unexpected response: ${resp['type']}');
    }

    final token = DeviceSessionToken(
      payload:                resp['token_payload']       as String,
      signatureBase64:        resp['token_signature']     as String,
      primaryPublicKeyBase64: resp['primary_public_key']  as String,
    );

    return DeviceSession(
      sessionId:         const Uuid().v4(),
      primaryIdentityId: resp['primary_device_id'] as String,
      token:             token,
    );
  }

  // ── Delta pull ────────────────────────────────────────────────────────────

  @override
  Future<int> pullDeltas({
    required DeviceSession session,
    DateTime? lastSyncAt,
  }) async {
    final body = <String, dynamic>{
      'type':           'delta_request',
      'token_payload':  session.token.payload,
      'token_signature': session.token.signatureBase64,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt.toIso8601String(),
    };

    final resp = await httpPost(
      '$apiBase/sync/delta',
      body,
      sessionToken: sessionToken,
    );

    if (resp['type'] == 'revocation') {
      throw const SyncException('Session revoked by phone');
    }
    if (resp['type'] != 'delta_response') {
      throw SyncException('Unexpected response: ${resp["type"]}');
    }

    final rows = (resp['rows'] as List<dynamic>)
        .map((r) => DeltaRow.fromJson(r as Map<String, dynamic>))
        .toList();

    if (rows.isEmpty) return 0;

    await dbHelper.withDatabase((db) async {
      for (final row in rows) {
        if (!_syncableTables.contains(row.table)) continue;
        if (row.isUpsert && row.payload != null) {
          await db.insert(
            row.table,
            row.payload!,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else if (row.isDelete) {
          await db.update(
            row.table,
            {'deleted_at': DateTime.now().toIso8601String()},
            where:     'sync_id = ?',
            whereArgs: [row.syncId],
          );
        }
      }
    });

    return rows.length;
  }

  // ── Delta push ────────────────────────────────────────────────────────────

  @override
  Future<int> pushDeltas({
    required DeviceSession session,
    required List<DeltaRow> rows,
  }) async {
    if (rows.isEmpty) return 0;

    final body = <String, dynamic>{
      'type':            'delta_upload',
      'token_payload':   session.token.payload,
      'token_signature': session.token.signatureBase64,
      'rows':            rows.map((r) => r.toJson()).toList(),
    };

    final resp = await httpPost(
      '$apiBase/sync/push',
      body,
      sessionToken: sessionToken,
    );

    if (resp['type'] != 'upload_ack') {
      throw SyncException('Push failed: ${resp["type"]}');
    }

    return (resp['received_count'] as int?) ?? rows.length;
  }

  @override
  Future<List<DeltaRow>> buildLocalDeltas({DateTime? since}) =>
      dbHelper.withDatabase((db) async {
        final rows = <DeltaRow>[];
        for (final table in _syncableTables) {
          try {
            final results = await db.query(
              table,
              where:     since != null ? 'updated_at > ?' : null,
              whereArgs: since != null ? [since.toIso8601String()] : null,
            );
            for (final row in results) {
              rows.add(DeltaRow(
                table:     table,
                syncId:    row['sync_id']    as String? ?? '',
                version:   row['version']    as int?    ?? 0,
                updatedAt: row['updated_at'] as String? ??
                           row['created_at'] as String? ??
                           DateTime.now().toIso8601String(),
                operation: row['deleted_at'] != null ? 'delete' : 'upsert',
                payload:   row['deleted_at'] == null
                    ? Map<String, dynamic>.from(row)
                    : null,
              ));
            }
          } catch (_) {
            continue;
          }
        }
        return rows;
      });
}
