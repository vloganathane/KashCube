import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../models/delta_row.dart';
import '../models/linked_device.dart';
import '../services/database_helper.dart';
import '../services/identity_service.dart';
import '../services/token_service.dart';
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

  // Tables that are synced in full for Owner Mirror
  static const List<String> _syncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
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

  Future<void> _handleConnection(Socket socket) async {
    _clients.add(socket);
    try {
      final msg = await _readMessage(socket);
      if (msg == null) return;

      final type = msg['type'] as String?;
      switch (type) {
        case 'pair_request':
          await _handlePairRequest(socket, msg);
        case 'delta_request':
          await _handleDeltaRequest(socket, msg);
        case 'delta_upload':
          await _handleDeltaUpload(socket, msg);
        default:
          await _sendMessage(socket, {'type': 'error', 'message': 'unknown_type'});
      }
    } catch (_) {
      // swallow per-connection errors
    } finally {
      _clients.remove(socket);
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

    // Build a new LinkedDevice record for the secondary
    final device = LinkedDevice(
      syncId:              _uuid(),
      deviceId:            secondaryDeviceId,
      deviceName:          secondaryDeviceName,
      deviceOs:            deviceOs,
      deviceType:          deviceType,
      secondaryPublicKey:  secondaryPublicKey,
      permissionScope:     '{}',
      businessScope:       '[]',
      offlineGraceDays:    7,
      preset:              DevicePreset.fromDb(presetStr),
    );

    await linkedDeviceRepo.insert(device);

    // Issue signed session token
    final token = await tokenService.issue(device);
    final primaryKeyB64  = await identity.publicKeyBase64;
    final primaryDeviceId = await identity.deviceId;

    await _sendMessage(socket, {
      'type':               'pair_response',
      'token_payload':      token.payload,
      'token_signature':    token.signatureBase64,
      'primary_public_key': primaryKeyB64,
      'primary_device_id':  primaryDeviceId,
    });
  }

  // ── Delta request (secondary wants rows) ─────────────────────────────────

  Future<void> _handleDeltaRequest(
    Socket socket,
    Map<String, dynamic> msg,
  ) async {
    if (!await _verifyDeviceToken(msg)) {
      await _sendMessage(socket, {'type': 'error', 'message': 'invalid_token'});
      return;
    }

    final lastSyncAt = msg['last_sync_at'] as String?;
    final rows = await _collectDeltas(since: lastSyncAt);

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

    final rawRows = (msg['rows'] as List<dynamic>?) ?? [];
    final rows = rawRows.map((r) => DeltaRow.fromJson(r as Map<String, dynamic>)).toList();
    await _applyDeltas(rows);

    await _sendMessage(socket, {
      'type':           'upload_ack',
      'received_count': rows.length,
    });
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

  Future<List<DeltaRow>> _collectDeltas({String? since}) =>
      dbHelper.withDatabase((db) async {
        final rows = <DeltaRow>[];
        for (final table in _syncableTables) {
          final results = await db.query(
            table,
            where:     since != null ? "updated_at > ?" : null,
            whereArgs: since != null ? [since] : null,
          );
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
        }
        return rows;
      });

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
              where: 'sync_id = ?',
              whereArgs: [row.syncId],
            );
          }
        }
      });

  // ── Framing ──────────────────────────────────────────────────────────────

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
      const Duration(seconds: 30),
      onTimeout: () { sub.cancel(); return null; },
    );
  }

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
}
