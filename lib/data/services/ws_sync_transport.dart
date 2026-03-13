import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/delta_row.dart';
import '../models/device_session_token.dart';
import 'database_helper.dart';
import 'identity_service.dart';
import 'sync_transport.dart';

/// WebSocket-based [SyncTransport] for the browser companion.
///
/// [open] connects to `ws://ip:port/ws?token=...` using [WebSocketChannel].
/// Speaks the same JSON message protocol as the TCP transport, minus the
/// 4-byte length prefix (WebSocket frames handle framing natively).
class WsSyncTransport implements SyncTransport {
  WsSyncTransport({
    required this.identity,
    required this.dbHelper,
  });

  final IdentityService identity;
  final DatabaseHelper  dbHelper;

  WebSocketChannel? _channel;

  // Tables the secondary can receive upserts for — mirrors SyncClient.
  static const List<String> _syncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
  ];

  // ── SyncTransport interface ───────────────────────────────────────────────

  @override
  Future<void> open(Uri endpoint) async {
    _channel = WebSocketChannel.connect(endpoint);
    await _channel!.ready;
  }

  @override
  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
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
    _assertOpen();
    final deviceId  = await identity.deviceId;
    final pubKeyB64 = await identity.publicKeyBase64;

    _send({
      'type':        'pair_request',
      'device_id':   deviceId,
      'device_name': deviceName,
      'public_key':  pubKeyB64,
      'device_os':   deviceOs,
      'device_type': deviceType,
      'preset':      preset,
      if (secondaryIdentityId  != null) 'secondary_identity_id':   secondaryIdentityId,
      if (secondaryDisplayName != null) 'secondary_display_name':  secondaryDisplayName,
    });

    final resp = await _recv();
    if (resp['type'] != 'pair_response') {
      throw const SyncException('Invalid pair_response from primary');
    }

    final token = DeviceSessionToken(
      payload:               resp['token_payload']      as String,
      signatureBase64:       resp['token_signature']    as String,
      primaryPublicKeyBase64: resp['primary_public_key'] as String,
    );

    return DeviceSession(
      sessionId:         const Uuid().v4(),
      primaryIdentityId: resp['primary_device_id'] as String,
      token:             token,
    );
  }

  // ── Delta sync ───────────────────────────────────────────────────────────

  @override
  Future<int> pullDeltas({
    required DeviceSession session,
    DateTime? lastSyncAt,
  }) async {
    _assertOpen();
    final deviceId = await identity.deviceId;
    _send({
      'type':            'delta_request',
      'device_id':       deviceId,
      'last_sync_at':    lastSyncAt?.toIso8601String(),
      'token_payload':   session.token.payload,
      'token_signature': session.token.signatureBase64,
    });

    final resp = await _recv();
    if (resp['type'] == 'revocation') {
      throw const SyncRevokedException('Device has been revoked by the primary');
    }
    if (resp['type'] != 'delta_response') {
      throw const SyncException('Invalid delta_response from primary');
    }

    final rawRows = (resp['rows'] as List<dynamic>?) ?? [];
    final rows = rawRows
        .map((r) => DeltaRow.fromJson(r as Map<String, dynamic>))
        .toList();
    await _applyDeltas(rows);
    return rows.length;
  }

  @override
  Future<int> pushDeltas({
    required DeviceSession session,
    required List<DeltaRow> rows,
  }) async {
    _assertOpen();
    final deviceId = await identity.deviceId;
    _send({
      'type':            'delta_upload',
      'device_id':       deviceId,
      'rows':            rows.map((r) => r.toJson()).toList(),
      'token_payload':   session.token.payload,
      'token_signature': session.token.signatureBase64,
    });

    final resp = await _recv();
    if (resp['type'] == 'revocation') {
      throw const SyncRevokedException('Device has been revoked by the primary');
    }
    if (resp['type'] != 'upload_ack') {
      throw const SyncException('Invalid upload_ack from primary');
    }
    return resp['received_count'] as int? ?? 0;
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> msg) =>
      _channel!.sink.add(jsonEncode(msg));

  Future<Map<String, dynamic>> _recv() async {
    final raw = await _channel!.stream.first
        .timeout(const Duration(seconds: 30));
    return jsonDecode(raw as String) as Map<String, dynamic>;
  }

  Future<void> _applyDeltas(List<DeltaRow> rows) =>
      dbHelper.withDatabase((db) async {
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

  void _assertOpen() {
    if (_channel == null) {
      throw const SyncException(
          'WsSyncTransport not open — call open() first');
    }
  }
}
