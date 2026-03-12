import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/delta_row.dart';
import '../models/device_session_token.dart';
import '../services/database_helper.dart';
import '../services/identity_service.dart';

/// TCP client that runs on the SECONDARY device.
///
/// Protocol mirrors [SyncServer]: every message is framed as:
///   [4-byte big-endian length][UTF-8 JSON payload]
class SyncClient {
  SyncClient({
    required this.identity,
    required this.dbHelper,
  });

  final IdentityService identity;
  final DatabaseHelper  dbHelper;

  Socket? _socket;

  bool get isConnected => _socket != null;

  // Tables that the secondary can accept upserts for
  static const List<String> _syncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
  ];

  /// Opens a TCP connection to the primary at [ip]:[port].
  Future<void> connect({required String ip, required int port}) async {
    _socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(seconds: 15),
    );
  }

  /// Closes the active connection.
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }

  // ── Pairing ──────────────────────────────────────────────────────────────

  /// Sends a `pair_request` to the primary and returns the issued token.
  ///
  /// The caller must already have called [connect].
  ///
  /// [secondaryIdentityId] and [secondaryDisplayName] are the permanent
  /// identity UUID and display name of THIS (secondary) device.  When
  /// provided, the primary stores them in the `linked_devices` row so the
  /// device list can show "Ravi Kumar" instead of "Ravi's Galaxy S23".
  Future<DeviceSession> sendPairRequest({
    required String preset,
    required String deviceOs,
    required String deviceType,
    required String deviceName,
    String? secondaryIdentityId,
    String? secondaryDisplayName,
  }) async {
    _assertConnected();
    final deviceId  = await identity.deviceId;
    final pubKeyB64 = await identity.publicKeyBase64;

    await _sendMessage(_socket!, {
      'type':        'pair_request',
      'device_id':   deviceId,
      'device_name': deviceName,
      'public_key':  pubKeyB64,
      'device_os':   deviceOs,
      'device_type': deviceType,
      'preset':      preset,
      'secondary_identity_id': ?secondaryIdentityId,
      'secondary_display_name': ?secondaryDisplayName,
    });

    final resp = await _readMessage(_socket!);
    if (resp == null || resp['type'] != 'pair_response') {
      throw const SyncException('Invalid pair_response from primary');
    }

    final token = DeviceSessionToken(
      payload:                 resp['token_payload']      as String,
      signatureBase64:         resp['token_signature']    as String,
      primaryPublicKeyBase64:  resp['primary_public_key'] as String,
    );

    return DeviceSession(
      sessionId:         const Uuid().v4(),
      primaryIdentityId: resp['primary_device_id'] as String,
      token:             token,
    );
  }

  // ── Delta sync ───────────────────────────────────────────────────────────

  /// Requests all rows changed since [lastSyncAt] from the primary.
  /// Applies received rows to the local database.
  /// Returns the count of rows applied.
  Future<int> pullDeltas({
    required DeviceSession session,
    DateTime? lastSyncAt,
  }) async {
    _assertConnected();

    final deviceId = await identity.deviceId;
    await _sendMessage(_socket!, {
      'type':            'delta_request',
      'device_id':       deviceId,
      'last_sync_at':    lastSyncAt?.toIso8601String(),
      'token_payload':   session.token.payload,
      'token_signature': session.token.signatureBase64,
    });

    final resp = await _readMessage(_socket!);
    if (resp == null) {
      throw const SyncException('No response from primary');
    }
    // Primary signals that this device has been revoked.
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

  /// Uploads local changes to the primary.
  /// Returns the [received_count] acknowledged by the primary.
  Future<int> pushDeltas({
    required DeviceSession session,
    required List<DeltaRow> rows,
  }) async {
    _assertConnected();

    final deviceId = await identity.deviceId;
    await _sendMessage(_socket!, {
      'type':            'delta_upload',
      'device_id':       deviceId,
      'rows':            rows.map((r) => r.toJson()).toList(),
      'token_payload':   session.token.payload,
      'token_signature': session.token.signatureBase64,
    });

    final resp = await _readMessage(_socket!);
    if (resp == null || resp['type'] != 'upload_ack') {
      throw const SyncException('Invalid upload_ack from primary');
    }
    return resp['received_count'] as int? ?? 0;
  }

  // ── Payroll notification fetch ───────────────────────────────────────────

  /// Requests pending payroll notifications from the primary, stores them
  /// locally in [payroll_notifications], and returns the count received.
  ///
  /// The primary filters by the secondary's permanent [secondaryIdentityId] so
  /// only this device's notifications are delivered — no cross-device leakage.
  Future<int> fetchPayrollNotifications({
    required DeviceSession session,
  }) async {
    _assertConnected();

    final deviceId = await identity.deviceId;
    await _sendMessage(_socket!, {
      'type':            'payroll_notification_request',
      'device_id':       deviceId,
      'token_payload':   session.token.payload,
      'token_signature': session.token.signatureBase64,
    });

    final resp = await _readMessage(_socket!);
    if (resp == null) {
      throw const SyncException('No response from primary');
    }
    if (resp['type'] == 'revocation') {
      throw const SyncRevokedException('Device has been revoked by the primary');
    }
    if (resp['type'] != 'payroll_notification_response') {
      throw const SyncException('Invalid payroll_notification_response from primary');
    }

    final rawList = (resp['notifications'] as List<dynamic>?) ?? [];
    if (rawList.isEmpty) return 0;

    await dbHelper.withDatabase((db) async {
      for (final item in rawList) {
        final n = item as Map<String, dynamic>;
        await db.insert(
          'payroll_notifications',
          {
            'notification_id':    n['notification_id'],
            'source_identity_id': n['source_identity_id'],
            'business_name':      n['business_name'],
            'amount':             n['amount'],
            'currency':           n['currency'] ?? 'INR',
            'reference_label':    n['reference_label'],
            'paid_on':            n['paid_on'],
            'status':             'pending',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    return rawList.length;
  }

  // ── Apply rows ───────────────────────────────────────────────────────────

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

  // ── Framing ──────────────────────────────────────────────────────────────

  Future<void> _sendMessage(Socket socket, Map<String, dynamic> msg) async {
    final payload = utf8.encode(jsonEncode(msg));
    final header  = ByteData(4)..setInt32(0, payload.length);
    socket.add(header.buffer.asUint8List());
    socket.add(payload);
    await socket.flush();
  }

  Future<Map<String, dynamic>?> _readMessage(Socket socket) async {
    final completer = Completer<Map<String, dynamic>?>();
    final buf = BytesBuilder();
    int? expectedLength;
    late StreamSubscription<Uint8List> sub;

    sub = socket.cast<Uint8List>().listen(
      (chunk) {
        buf.add(chunk);
        final bytes = buf.toBytes();
        if (expectedLength == null && bytes.length >= 4) {
          expectedLength = ByteData.sublistView(bytes, 0, 4).getInt32(0);
        }
        if (expectedLength != null && bytes.length >= 4 + expectedLength!) {
          sub.cancel();
          try {
            final json = utf8.decode(bytes.sublist(4, 4 + expectedLength!));
            completer.complete(jsonDecode(json) as Map<String, dynamic>);
          } catch (_) {
            completer.complete(null);
          }
        }
      },
      onError: (_) => completer.complete(null),
      onDone: () { if (!completer.isCompleted) completer.complete(null); },
    );

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () { sub.cancel(); return null; },
    );
  }

  void _assertConnected() {
    if (_socket == null) {
      throw const SyncException('SyncClient not connected — call connect() first');
    }
  }
}

/// Thrown when a sync operation fails due to a protocol error.
/// Thrown for general protocol-level errors during sync.
class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => 'SyncException: $message';
}

/// Thrown when the primary reports that this secondary device has been revoked.
/// The caller must wipe the local [DeviceSessionService] session.
class SyncRevokedException extends SyncException {
  const SyncRevokedException(super.message);
  @override
  String toString() => 'SyncRevokedException: $message';
}
