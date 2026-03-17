import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'sync_framing.dart';

import '../models/app_user.dart';
import '../models/delta_row.dart';
import '../models/linked_device.dart';
import '../services/database_helper.dart';
import '../services/fiscal_year_service.dart';
import '../services/identity_service.dart';
import '../services/number_reservation_service.dart';
import '../services/token_service.dart';
import '../../domain/models/permission.dart';
import '../../domain/repositories/linked_device_repository.dart';

/// TCP server that runs on the PRIMARY device.
///
/// Protocol: every message is framed as:
///   [4-byte big-endian length][UTF-8 JSON payload]
///
/// Accepted message types:
/// - `pair_request`   — secondary wants to pair
/// - `delta_request`  — secondary wants deltas since [last_sync_at]
/// - `delta_upload`   — secondary sending its local changes
class SyncServer {
  SyncServer({
    required this.identity,
    required this.tokenService,
    required this.linkedDeviceRepo,
    required this.dbHelper,
  });

  final IdentityService         identity;
  final TokenService            tokenService;
  final LinkedDeviceRepository  linkedDeviceRepo;
  final DatabaseHelper          dbHelper;

  ServerSocket? _serverSocket;
  final List<Socket> _clients = [];

  int get port => _serverSocket?.port ?? 0;
  bool get isRunning => _serverSocket != null;

  // All tables that participate in sync.
  static const List<String> _syncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
  ];

  // Subset of syncable tables that have a business_id column.
  // Only these are delivered to non-owner-mirror secondary devices.
  static const List<String> _businessScopedTables = [
    'transactions', 'credits', 'credit_payments', 'loans', 'budgets',
  ];

  /// Starts listening on a random free port.  Returns the assigned port.
  Future<int> start() async {
    if (_serverSocket != null) return port;
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _serverSocket!.listen(_handleConnection, onError: (Object e) {
      // log and ignore individual accept errors
    });
    return _serverSocket!.port;
  }

  /// Stops the server and closes all open client connections.
  Future<void> stop() async {
    for (final c in _clients) {
      await c.close();
    }
    _clients.clear();
    await _serverSocket?.close();
    _serverSocket = null;
  }

  // ── Connection handler ───────────────────────────────────────────────────

  /// Handles a client connection as a persistent message loop.
  ///
  /// A single TCP connection can carry N sequential operations
  /// (pair → pull → push → reserve_number, etc.) rather than one message
  /// per connect-disconnect cycle.
  ///
  /// Keepalive: after [_kPingInterval] of idle the server sends a `ping`
  /// frame.  The client is expected to reply with `pong` (handled by
  /// [SyncClient._readResponse]).  If no message arrives within
  /// [_kReadTimeout] the connection is silently closed.
  static const Duration _kPingInterval = Duration(seconds: 30);
  static const Duration _kReadTimeout  = Duration(seconds: 60);

  Future<void> _handleConnection(Socket socket) async {
    _clients.add(socket);
    debugPrint('[DeviceLink] SyncServer: new connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    final reader = FrameReader(socket);
    Timer? pingTimer;

    void resetPingTimer() {
      pingTimer?.cancel();
      pingTimer = Timer(_kPingInterval, () {
        // Send a keepalive ping.  Errors mean the socket is already dead.
        _sendMessage(socket, {'type': 'ping'}).catchError((_) {});
      });
    }

    try {
      resetPingTimer();
      while (true) {
        final msg = await reader.readMessage(timeout: _kReadTimeout);
        if (msg == null) break; // connection closed or timed out
        resetPingTimer();

        final type = msg['type'] as String?;
        debugPrint('[DeviceLink] SyncServer: received message type="$type" from ${socket.remoteAddress.address}');
        switch (type) {
          case 'pong':
            break; // keepalive reply — timer already reset above, nothing else to do
          case 'pair_request':
            try {
              await _handlePairRequest(socket, msg);
            } catch (e) {
              // Send an error response so the secondary doesn't wait for a timeout.
              try {
                await _sendMessage(socket, {
                  'type':    'pair_error',
                  'message': e.toString(),
                });
              } catch (_) {}
              rethrow;
            }
          case 'delta_request':
            await _handleDeltaRequest(socket, msg);
          case 'delta_upload':
            await _handleDeltaUpload(socket, msg);
          case 'payroll_notification_request':
            await _handlePayrollNotificationRequest(socket, msg);
          case 'reserve_number':
            await _handleReserveNumber(socket, msg);
          default:
            await _sendMessage(socket, {'type': 'error', 'message': 'unknown_type'});
        }
      }
    } catch (e) {
      debugPrint('[DeviceLink] SyncServer: connection error: $e');
    } finally {
      pingTimer?.cancel();
      reader.dispose();
      _clients.remove(socket);
      debugPrint('[DeviceLink] SyncServer: connection closed (${socket.remoteAddress.address}:${socket.remotePort})');
      await socket.close();
    }
  }

  // ── Pair ─────────────────────────────────────────────────────────────────

  Future<void> _handlePairRequest(
    Socket socket,
    Map<String, dynamic> msg,
  ) async {
    final secondaryDeviceId  = msg['device_id']   as String;
    final secondaryDeviceName = msg['device_name'] as String;
    final secondaryPublicKey  = msg['public_key']  as String;
    final deviceOs            = msg['device_os']   as String?;
    final deviceType          = msg['device_type'] as String?;
    final presetStr           = msg['preset']      as String? ?? 'owner_mirror';
    // D3: identity-first pairing — secondary sends its identity info
    final secondaryIdentityId   = msg['secondary_identity_id']   as String?;
    final secondaryDisplayName  = msg['secondary_display_name']  as String?;

    debugPrint('[DeviceLink] SyncServer._handlePairRequest: deviceId=$secondaryDeviceId, name=$secondaryDeviceName, os=$deviceOs, preset=$presetStr, identityId=$secondaryIdentityId, displayName=$secondaryDisplayName');

    final preset = DevicePreset.fromDb(presetStr);

    // Build a new LinkedDevice record for the secondary.
    // permissionScope is seeded from the role preset so the secondary can
    // enforce its own UI gates without a DB round-trip.
    final device = LinkedDevice(
      syncId:              _uuid(),
      deviceId:            secondaryDeviceId,
      deviceName:          secondaryDeviceName,
      deviceOs:            deviceOs,
      deviceType:          deviceType,
      secondaryPublicKey:  secondaryPublicKey,
      permissionScope:     _permScopeForPreset(preset),
      businessScope:       '[]',  // admin configures scope in DeviceDetailScreen
      offlineGraceDays:    7,
      preset:              preset,
      secondaryIdentityId:  secondaryIdentityId,
      secondaryDisplayName: secondaryDisplayName,
    );

    await linkedDeviceRepo.insert(device);
    debugPrint('[DeviceLink] SyncServer: linked_device row inserted (syncId=${device.syncId})');

    // Load primary's plan features to embed in the token.
    final planFeatures = await dbHelper.withDatabase(_loadPlanFeaturesForToken);

    // Issue signed session token
    final token = await tokenService.issue(device, planFeatures: planFeatures);
    final primaryKeyB64  = await identity.publicKeyBase64;
    final primaryDeviceId = await identity.deviceId;

    debugPrint('[DeviceLink] SyncServer: sending pair_response to $secondaryDeviceName');
    await _sendMessage(socket, {
      'type':               'pair_response',
      'token_payload':      token.payload,
      'token_signature':    token.signatureBase64,
      'primary_public_key': primaryKeyB64,
      'primary_device_id':  primaryDeviceId,
    });
    debugPrint('[DeviceLink] SyncServer: pair_response sent successfully');
  }

  /// Queries the local subscription + plan_features tables and returns a
  /// feature map suitable for embedding in the session token.
  ///
  /// Also caches the serialised features in `subscription.shareable_plan_features`
  /// so it can be used efficiently on subsequent syncs.
  Future<Map<String, dynamic>> _loadPlanFeaturesForToken(Database db) async {
    final subRows = await db.query('subscription', limit: 1);
    final plan = subRows.isNotEmpty
        ? (subRows.first['plan'] as String? ?? 'free')
        : 'free';

    final featureRows = await db.query(
      'plan_features',
      where: 'plan = ?',
      whereArgs: [plan],
    );

    final features = <String, dynamic>{};
    for (final row in featureRows) {
      features[row['feature'] as String] = {
        'enabled': (row['enabled'] as int?) == 1,
        'limit':   row['limit_value'] as int? ?? 0,
      };
    }

    // Cache serialised features for quick access on future syncs.
    if (subRows.isNotEmpty) {
      await db.update(
        'subscription',
        {'shareable_plan_features': jsonEncode(features)},
      );
    }

    return features;
  }

  // ── Delta request (secondary wants rows) ─────────────────────────────────

  Future<void> _handleDeltaRequest(
    Socket socket,
    Map<String, dynamic> msg,
  ) async {
    // 1. Verify token signature.
    if (!await _verifyDeviceToken(msg)) {
      await _sendMessage(socket, {'type': 'error', 'message': 'invalid_token'});
      return;
    }

    // 2. Look up the LinkedDevice to check revocation + scope.
    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      // Device was revoked — tell the secondary to wipe its session.
      await _sendMessage(socket, {
        'type':    'revocation',
        'message': 'device_revoked',
      });
      return;
    }

    // 3. Build a permission-scoped delta and send it.
    final lastSyncAt = msg['last_sync_at'] as String?;
    final rows = await _collectDeltas(since: lastSyncAt, device: device);

    await _sendMessage(socket, {
      'type':        'delta_response',
      'rows':        rows.map((r) => r.toJson()).toList(),
      'server_time': DateTime.now().toIso8601String(),
    });
  }

  // ── Delta upload (secondary pushes its changes) ──────────────────────────

  Future<void> _handleDeltaUpload(
    Socket socket,
    Map<String, dynamic> msg,
  ) async {
    if (!await _verifyDeviceToken(msg)) {
      await _sendMessage(socket, {'type': 'error', 'message': 'invalid_token'});
      return;
    }

    // Check revocation before accepting any writes.
    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      await _sendMessage(socket, {'type': 'revocation', 'message': 'device_revoked'});
      return;
    }

    final rawRows = (msg['rows'] as List<dynamic>?) ?? [];
    final rows = rawRows
        .map((r) => DeltaRow.fromJson(r as Map<String, dynamic>))
        .toList();
    await _applyDeltas(rows, device: device);

    await _sendMessage(socket, {
      'type':           'upload_ack',
      'received_count': rows.length,
    });
  }

  // ── Payroll notification delivery ────────────────────────────────────────

  /// Delivers pending payroll notifications to a secondary device, filtered
  /// by the secondary's permanent [secondaryIdentityId].
  ///
  /// Only the specifically-targeted secondary receives its own notifications —
  /// no cross-device leakage.
  Future<void> _handlePayrollNotificationRequest(
    Socket socket,
    Map<String, dynamic> msg,
  ) async {
    if (!await _verifyDeviceToken(msg)) {
      await _sendMessage(socket, {'type': 'error', 'message': 'invalid_token'});
      return;
    }

    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      await _sendMessage(socket, {
        'type':    'revocation',
        'message': 'device_revoked',
      });
      return;
    }

    final identityId = device.secondaryIdentityId;
    if (identityId == null) {
      await _sendMessage(socket, {
        'type':          'payroll_notification_response',
        'notifications': <dynamic>[],
      });
      return;
    }

    // Query pending outbox events for this identity.
    final rows = await dbHelper.withDatabase(
      (db) => db.query(
        'sync_outbox',
        where:     'event_type = ? AND target_identity_id = ? AND delivered_at IS NULL',
        whereArgs: ['payroll_notification', identityId],
      ),
    );

    // Mark as delivered before sending (at-most-once delivery).
    if (rows.isNotEmpty) {
      final ids = rows.map((r) => r['id'] as int).toList();
      await dbHelper.withDatabase(
        (db) => db.update(
          'sync_outbox',
          {'delivered_at': DateTime.now().toIso8601String()},
          where:     'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        ),
      );
    }

    final events = rows
        .map((r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>)
        .toList();

    await _sendMessage(socket, {
      'type':          'payroll_notification_response',
      'notifications': events,
    });
  }

  // ── Reserve Number ────────────────────────────────────────────────────────

  /// Atomically reserves one or more sequential document numbers on behalf of
  /// a secondary device.  The secondary must supply its session token so the
  /// primary can confirm it is still active before issuing a number.
  Future<void> _handleReserveNumber(
    Socket socket,
    Map<String, dynamic> msg,
  ) async {
    if (!await _verifyDeviceToken(msg)) {
      await _sendMessage(socket, {'type': 'error', 'message': 'invalid_token'});
      return;
    }

    final docType = msg['doc_type'] as String?;
    final count   = (msg['count'] as num?)?.toInt() ?? 1;

    if (docType == null || count < 1 || count > 100) {
      await _sendMessage(socket, {
        'type':    'error',
        'message': 'reserve_number_failed',
        'detail':  'invalid doc_type or count',
      });
      return;
    }

    try {
      final fyService = FiscalYearService.instance;
      final now       = DateTime.now();
      final fy        = await fyService.getFiscalYearFor(now);
      final format    = await _formatForDocType(fyService, docType);
      final prefix    = fyService.computePrefix(format, fy);

      final numbers = await dbHelper.withDatabase(
        (db) => NumberReservationService.instance.reserveNext(
          db,
          docType: docType,
          prefix:  prefix,
          count:   count,
        ),
      );

      await _sendMessage(socket, {
        'type':     'number_reserved',
        'doc_type': docType,
        'numbers':  numbers,
      });
    } catch (e) {
      await _sendMessage(socket, {
        'type':    'error',
        'message': 'reserve_number_failed',
        'detail':  e.toString(),
      });
    }
  }

  Future<String> _formatForDocType(
    FiscalYearService fyService,
    String docType,
  ) async {
    switch (docType) {
      case 'invoice':
        return fyService.invoiceNoFormat;
      case 'quote':
        return fyService.quoteNoFormat;
      case 'dc':
        return fyService.challanNoFormat;
      case 'credit_note':
        return 'CN-{YY}-{YY+1}-{SEQ}';
      case 'debit_note':
        return 'DN-{YY}-{YY+1}-{SEQ}';
      default:
        return 'DOC-{YY}-{YY+1}-{SEQ}';
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<bool> _verifyDeviceToken(Map<String, dynamic> msg) async {
    // Primary verifies the token that it originally issued.
    // The signature on the token was made by the primary's own private key,
    // so we can verify with our own public key.
    final tokenPayload   = msg['token_payload']   as String?;
    final tokenSig       = msg['token_signature'] as String?;
    if (tokenPayload == null || tokenSig == null) return false;
    final pubKeyB64 = await identity.publicKeyBase64;
    return identity.verify(
      message:         utf8.encode(tokenPayload),
      sigBase64:       tokenSig,
      publicKeyBase64: pubKeyB64,
    );
  }

  Future<List<DeltaRow>> _collectDeltas({
    String? since,
    LinkedDevice? device,
  }) =>
      dbHelper.withDatabase((db) async {
        final isOwner = device?.isOwnerMirror ?? true;

        // Parse business_scope for non-owner-mirror devices.
        List<int> businessIds = [];
        if (!isOwner && device != null) {
          final parsed = jsonDecode(device.businessScope) as List<dynamic>;
          businessIds = parsed.cast<int>();
        }

        final tables = isOwner ? _syncableTables : _businessScopedTables;
        final rows   = <DeltaRow>[];

        for (final table in tables) {
          try {
            late List<Map<String, dynamic>> results;

            if (isOwner) {
              results = await db.query(
                table,
                where:     since != null ? 'updated_at > ?' : null,
                whereArgs: since != null ? [since] : null,
              );
            } else if (businessIds.isEmpty) {
              // Empty scope → no data for this device yet.
              results = [];
            } else {
              final ph  = businessIds.map((_) => '?').join(',');
              final where = 'business_id IS NOT NULL AND business_id IN ($ph)'
                  '${since != null ? ' AND updated_at > ?' : ''}';
              final args = <Object?>[...businessIds, ?since];
              results = await db.rawQuery(
                'SELECT * FROM $table WHERE $where',
                args,
              );
            }

            for (final row in results) {
              rows.add(DeltaRow(
                table:     table,
                syncId:    row['sync_id'] as String? ?? '',
                version:   row['version'] as int? ?? 0,
                updatedAt: row['updated_at'] as String? ??
                           row['created_at'] as String? ??
                           DateTime.now().toIso8601String(),
                operation: 'upsert',
                payload:   Map<String, dynamic>.from(row),
              ));
            }
          } catch (_) {
            // Table doesn't have the expected column — skip gracefully.
            continue;
          }
        }
        return rows;
      });

  Future<void> _applyDeltas(
    List<DeltaRow> rows, {
    LinkedDevice? device,
  }) =>
      dbHelper.withDatabase((db) async {
        final isOwner = device?.isOwnerMirror ?? true;
        List<int> businessIds = [];
        if (!isOwner && device != null) {
          final parsed = jsonDecode(device.businessScope) as List<dynamic>;
          businessIds = parsed.cast<int>();
        }

        for (final row in rows) {
          if (!_syncableTables.contains(row.table)) continue;

          // For non-owner-mirror: only accept rows within the business scope.
          if (!isOwner) {
            if (businessIds.isEmpty) continue;
            final payload = row.payload;
            if (payload == null) continue;
            final bid = payload['business_id'];
            if (bid == null || !businessIds.contains(bid as int)) continue;
          }

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

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── Permission scope builder ─────────────────────────────────────────────

  /// Builds a JSON permission scope string for the given [preset].
  ///
  /// Owner Mirror always gets `'{}'` (the primary's own permission check
  /// applies — no token gate needed on the secondary for owner mirrors).
  /// For other presets, the scope is built from [RolePreset.forModule].
  static String _permScopeForPreset(DevicePreset preset) {
    if (preset == DevicePreset.ownerMirror) return '{}';

    late AppUserRole role;
    switch (preset) {
      case DevicePreset.manager:
        role = AppUserRole.manager;
      case DevicePreset.cashier:
        role = AppUserRole.cashier;
      case DevicePreset.auditor:
        role = AppUserRole.auditor;
      default:
        role = AppUserRole.custom;
    }

    final scope = <String, Map<String, bool>>{};
    for (final module in PermissionModule.all) {
      final p = RolePreset.forModule(role, module);
      scope[module] = {
        'canView':   p.canView,
        'canCreate': p.canCreate,
        'canEdit':   p.canEdit,
        'canDelete': p.canDelete,
      };
    }
    return jsonEncode(scope);
  }
}
