import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/delta_row.dart';
import '../models/linked_device.dart';
import '../repositories/linked_device_repository_impl.dart';
import '../../domain/models/permission.dart';
import '../../domain/repositories/linked_device_repository.dart';
import 'database_helper.dart';
import 'fiscal_year_service.dart';
import 'identity_service.dart';
import 'number_reservation_service.dart';
import 'token_service.dart';

/// Runs on the phone. Serves the KashCube WebSocket endpoint over LAN.
///
/// The Flutter Web companion (`web.kashcube.com`) connects to `/ws` after
/// scanning the QR code. All data stays on the LAN — the WhatsApp Web model.
///
/// Privacy guarantee: no data leaves the phone; the server is WS-only.
///
/// Lifecycle (via [WebServerProvider]):
/// ```dart
/// await WebServerService.instance.start(spaHtml: html);
/// final qr = WebServerService.instance.qrPayload;
/// // ...
/// await WebServerService.instance.stop();
/// ```
class WebServerService {
  WebServerService._();
  static final WebServerService instance = WebServerService._();

  static const int _defaultPort = 8080;

  HttpServer? _server;
  String? _sessionToken;
  String? _webDeviceId;   // device_id of the active linked_devices row
  DateTime? _lastTouchAt; // debounces last_sync_at DB writes

  /// WebSocket clients subscribed to real-time events.
  final List<WebSocketChannel> _wsClients = [];

  // ── Sync handler dependencies (lazy — initialised on first use) ──────────
  IdentityService get _identity       => IdentityService.instance;
  TokenService    get _tokenService   => TokenService(_identity);
  final LinkedDeviceRepository _linkedDeviceRepo = LinkedDeviceRepositoryImpl();

  bool get isRunning => _server != null;
  String? get sessionToken => _sessionToken;
  int? get port => _server?.port;

  /// Local base URL (http://192.168.x.x:8080).
  String? get localUrl {
    if (_server == null) return null;
    final ip = _lanIp ?? _server!.address.address;
    return 'http://$ip:${_server!.port}';
  }

  /// QR payload for the browser companion (JSON, type kashcube_web_v1).
  ///
  /// The browser parses this to get the WS URL and session token.
  /// WS URL: `ws://ip:port/ws?token=<token>`
  String? get qrPayload {
    final url = localUrl;
    if (url == null || _sessionToken == null) return null;
    final ip   = _lanIp ?? _server!.address.address;
    final port = _server!.port;
    return jsonEncode({
      'type':    'kashcube_web_v1',
      'ws':      'ws://$ip:$port/ws',
      'token':   _sessionToken,
      'version': 1,
    });
  }

  String? _lanIp;

  // ── Start / Stop ──────────────────────────────────────────────────────────

  Future<void> start({int port = _defaultPort}) async {
    if (isRunning) return;

    _sessionToken = const Uuid().v4().replaceAll('-', '');
    _lanIp = await _resolveLanIp();
    await _registerWebSession();

    // Flutter Web companion connects here for delta sync and live-refresh push.
    // The WS handler is mounted WITHOUT any async middleware wrapper so the
    // HijackException thrown by shelf_web_socket propagates to shelf_io.
    final wsHandler = webSocketHandler(
      (WebSocketChannel channel, String? _) {
        _wsClients.add(channel);
        channel.stream.listen(
          (data) async {
            try {
              final msg  = jsonDecode(data as String) as Map<String, dynamic>;
              final resp = await _handleSyncMessage(msg);
              channel.sink.add(jsonEncode(resp));
            } catch (_) {}
          },
          onDone:  () => _wsClients.remove(channel),
          onError: (_) => _wsClients.remove(channel),
        );
      },
    );

    final handler = Router()
      ..get('/ws', (Request req) {
        // Token check before upgrade — returns plain 401 on failure.
        final token = req.url.queryParameters['token'];
        if (token == null || token != _sessionToken) {
          return Response(
            401,
            body: jsonEncode({'error': 'Unauthorized'}),
            headers: {'content-type': 'application/json'},
          );
        }
        return wsHandler(req);
      });

    _server = await shelf_io.serve(handler.call, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    if (_server == null) return;
    for (final c in List.of(_wsClients)) {
      await c.sink.close();
    }
    _wsClients.clear();
    await _server!.close(force: true);
    await _revokeWebSession();
    _server = null;
    _sessionToken = null;
  }

  /// Regenerate token — existing browser sessions are immediately invalidated.
  /// A new [linked_devices] row is inserted so the next browser scan appears
  /// in the Linked Devices list with its own last-active timestamp.
  Future<void> revokeSession() async {
    await _revokeWebSession();
    _sessionToken = const Uuid().v4().replaceAll('-', '');
    await _registerWebSession();
    _push({'event': 'session_revoked'});
  }

  /// Kills the current web session without creating a new one.
  /// Called when the user revokes the web device from Linked Devices screen.
  Future<void> killWebSession() async {
    await _revokeWebSession();
    _sessionToken = null;
  }

  // ── Web session DB helpers ────────────────────────────────────────────────

  Future<void> _registerWebSession() async {
    final newId  = const Uuid().v4();
    final syncId = const Uuid().v4().replaceAll('-', '');
    _webDeviceId = newId;
    await DatabaseHelper.instance.withDatabase((db) async {
      await db.insert(
        'linked_devices',
        {
          'sync_id':              syncId,
          'device_id':            newId,
          'device_name':          'KashCube Web',
          'device_type':          'web',
          'device_os':            'browser',
          'secondary_public_key': '',
          'permission_scope':     '{"read": true}',
          'business_scope':       '[]',
          'offline_grace_days':   0,
          'created_at':           DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<void> _revokeWebSession() async {
    final id = _webDeviceId;
    if (id == null) return;
    _webDeviceId = null;
    await DatabaseHelper.instance.withDatabase((db) async {
      await db.update(
        'linked_devices',
        {'revoked_at': DateTime.now().toIso8601String()},
        where:     'device_id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Updates `last_sync_at` on the web session row, debounced to once/minute.
  Future<void> _touchLastActive() async {
    final id  = _webDeviceId;
    final now = DateTime.now();
    if (id == null) return;
    if (_lastTouchAt != null &&
        now.difference(_lastTouchAt!) < const Duration(minutes: 1)) {
      return;
    }
    _lastTouchAt = now;
    await DatabaseHelper.instance.withDatabase((db) async {
      await db.update(
        'linked_devices',
        {'last_sync_at': now.toIso8601String()},
        where:     'device_id = ?',
        whereArgs: [id],
      );
    });
  }

  // ── Real-time push ────────────────────────────────────────────────────────

  void _push(Map<String, dynamic> event) {
    final payload = jsonEncode(event);
    for (final c in List.of(_wsClients)) {
      try {
        c.sink.add(payload);
      } catch (_) {
        _wsClients.remove(c);
      }
    }
  }

  /// Notify connected browsers that a transaction was created/updated.
  void notifyTransactionChange(Map<String, dynamic> txn,
      {bool created = true}) {
    _push({
      'event': created ? 'transaction_created' : 'transaction_updated',
      'data': txn,
    });
  }

  /// Notify connected browsers that data in [tables] has changed so they
  /// trigger an auto-sync to pull the latest rows.
  void notifyDataChanged(List<String> tables) {
    if (!isRunning) return;
    _push({'event': 'data_changed', 'tables': tables});
  }

  /// Push a payroll notification event to connected browsers so they can
  /// surface an in-app alert without a full sync round-trip.
  void pushPayrollEvent(Map<String, dynamic> notification) {
    if (!isRunning) return;
    _push({'event': 'payroll_notification', 'data': notification});
  }

  // ── LAN IP ────────────────────────────────────────────────────────────────

  static Future<String?> _resolveLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (iface.name.toLowerCase().contains('wlan') ||
            iface.name.toLowerCase().contains('en') ||
            iface.name.toLowerCase().contains('wifi')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
  // ── WebSocket sync protocol handlers ─────────────────────────────────────
  //
  // Mirrors SyncServer message handling over WebSocket.
  // On web the browser is the secondary device; messages arrive over the
  // same `/ws` connection used for live-refresh push events.

  /// Routes an incoming WS message to the appropriate sync handler.
  /// Returns the response map to be JSON-encoded and sent back.
  Future<Map<String, dynamic>> _handleSyncMessage(
      Map<String, dynamic> msg) async {
    switch (msg['type'] as String?) {
      case 'pair_request':
        return _wsHandlePairRequest(msg);
      case 'delta_request':
        return _wsHandleDeltaRequest(msg);
      case 'delta_upload':
        return _wsHandleDeltaUpload(msg);
      case 'reserve_number':
        return _wsHandleReserveNumber(msg);
      default:
        return {'type': 'error', 'message': 'unknown_type'};
    }
  }

  Future<Map<String, dynamic>> _wsHandlePairRequest(
      Map<String, dynamic> msg) async {
    final secondaryDeviceId   = msg['device_id']   as String;
    final secondaryDeviceName = msg['device_name']  as String;
    final secondaryPublicKey  = msg['public_key']   as String;
    final deviceOs            = msg['device_os']    as String?;
    final deviceType          = msg['device_type']  as String?;
    final presetStr           = msg['preset']       as String? ?? 'owner_mirror';
    final secondaryIdentityId  = msg['secondary_identity_id']  as String?;
    final secondaryDisplayName = msg['secondary_display_name'] as String?;

    final preset = DevicePreset.fromDb(presetStr);
    final syncId = const Uuid().v4().replaceAll('-', '');

    final device = LinkedDevice(
      syncId:               syncId,
      deviceId:             secondaryDeviceId,
      deviceName:           secondaryDeviceName,
      deviceOs:             deviceOs,
      deviceType:           deviceType,
      secondaryPublicKey:   secondaryPublicKey,
      permissionScope:      _wsPermScopeForPreset(preset),
      businessScope:        '[]',
      offlineGraceDays:     7,
      preset:               preset,
      secondaryIdentityId:  secondaryIdentityId,
      secondaryDisplayName: secondaryDisplayName,
    );

    await _linkedDeviceRepo.insert(device);

    final planFeatures =
        await DatabaseHelper.instance.withDatabase(_wsLoadPlanFeatures);

    final token          = await _tokenService.issue(device, planFeatures: planFeatures);
    final primaryKeyB64  = await _identity.publicKeyBase64;
    final primaryDeviceId = await _identity.deviceId;

    return {
      'type':               'pair_response',
      'token_payload':      token.payload,
      'token_signature':    token.signatureBase64,
      'primary_public_key': primaryKeyB64,
      'primary_device_id':  primaryDeviceId,
    };
  }

  Future<Map<String, dynamic>> _wsHandleDeltaRequest(
      Map<String, dynamic> msg) async {
    if (!await _wsVerifyToken(msg)) {
      return {'type': 'error', 'message': 'invalid_token'};
    }

    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await _linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      return {'type': 'revocation', 'message': 'device_revoked'};
    }

    final lastSyncAt = msg['last_sync_at'] as String?;
    final rows = await _wsCollectDeltas(since: lastSyncAt, device: device);

    return {
      'type':        'delta_response',
      'rows':        rows.map((r) => r.toJson()).toList(),
      'server_time': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _wsHandleDeltaUpload(
      Map<String, dynamic> msg) async {
    if (!await _wsVerifyToken(msg)) {
      return {'type': 'error', 'message': 'invalid_token'};
    }

    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await _linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      return {'type': 'revocation', 'message': 'device_revoked'};
    }

    final rawRows = (msg['rows'] as List<dynamic>?) ?? [];
    final rows =
        rawRows.map((r) => DeltaRow.fromJson(r as Map<String, dynamic>)).toList();
    await _wsApplyDeltas(rows, device: device);

    return {'type': 'upload_ack', 'received_count': rows.length};
  }

  // ── Sync helpers ──────────────────────────────────────────────────────────

  static const List<String> _wsSyncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
  ];

  static const List<String> _wsBusinessScopedTables = [
    'transactions', 'credits', 'credit_payments', 'loans', 'budgets',
  ];

  Future<bool> _wsVerifyToken(Map<String, dynamic> msg) async {
    final tokenPayload = msg['token_payload']   as String?;
    final tokenSig     = msg['token_signature'] as String?;
    if (tokenPayload == null || tokenSig == null) return false;
    final pubKeyB64 = await _identity.publicKeyBase64;
    return _identity.verify(
      message:         utf8.encode(tokenPayload),
      sigBase64:       tokenSig,
      publicKeyBase64: pubKeyB64,
    );
  }

  Future<List<DeltaRow>> _wsCollectDeltas({
    String? since,
    LinkedDevice? device,
  }) =>
      DatabaseHelper.instance.withDatabase((db) async {
        final isOwner     = device?.isOwnerMirror ?? true;
        List<int> bizIds  = [];
        if (!isOwner && device != null) {
          bizIds =
              (jsonDecode(device.businessScope) as List<dynamic>).cast<int>();
        }

        final tables = isOwner ? _wsSyncableTables : _wsBusinessScopedTables;
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
            } else {
              if (bizIds.isEmpty) continue;
              final placeholders = bizIds.map((_) => '?').join(',');
              results = since != null
                  ? await db.rawQuery(
                      'SELECT * FROM $table WHERE updated_at > ? AND business_id IN ($placeholders)',
                      [since, ...bizIds],
                    )
                  : await db.rawQuery(
                      'SELECT * FROM $table WHERE business_id IN ($placeholders)',
                      bizIds,
                    );
            }
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

  Future<void> _wsApplyDeltas(List<DeltaRow> rows,
      {LinkedDevice? device}) =>
      DatabaseHelper.instance.withDatabase((db) async {
        final isOwner    = device?.isOwnerMirror ?? true;
        List<int> bizIds = [];
        if (!isOwner && device != null) {
          bizIds =
              (jsonDecode(device.businessScope) as List<dynamic>).cast<int>();
        }
        for (final row in rows) {
          if (!_wsSyncableTables.contains(row.table)) continue;
          if (!isOwner) {
            if (bizIds.isEmpty) continue;
            final bid = row.payload?['business_id'];
            if (bid == null || !bizIds.contains(bid as int)) continue;
          }
          if (row.isUpsert && row.payload != null) {
            await db.insert(row.table, row.payload!,
                conflictAlgorithm: ConflictAlgorithm.replace);
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

  // ── Reserve Number (WS) ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> _wsHandleReserveNumber(
    Map<String, dynamic> msg,
  ) async {
    if (!await _wsVerifyToken(msg)) {
      return {'type': 'error', 'message': 'invalid_token'};
    }

    final docType = msg['doc_type'] as String?;
    final count   = (msg['count'] as num?)?.toInt() ?? 1;

    if (docType == null || count < 1 || count > 100) {
      return {
        'type':    'error',
        'message': 'reserve_number_failed',
        'detail':  'invalid doc_type or count',
      };
    }

    try {
      final fyService = FiscalYearService.instance;
      final now       = DateTime.now();
      final fy        = await fyService.getFiscalYearFor(now);
      final format    = await _formatForDocType(fyService, docType);
      final prefix    = fyService.computePrefix(format, fy);

      final numbers = await DatabaseHelper.instance.withDatabase(
        (db) => NumberReservationService.instance.reserveNext(
          db,
          docType: docType,
          prefix:  prefix,
          count:   count,
        ),
      );

      return {
        'type':     'number_reserved',
        'doc_type': docType,
        'numbers':  numbers,
      };
    } catch (e) {
      return {
        'type':    'error',
        'message': 'reserve_number_failed',
        'detail':  e.toString(),
      };
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

  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _wsLoadPlanFeatures(Database db) async {
    final subRows = await db.query('subscription', limit: 1);
    final plan = subRows.isNotEmpty
        ? (subRows.first['plan'] as String? ?? 'free')
        : 'free';
    final featureRows = await db.query('plan_features',
        where: 'plan = ?', whereArgs: [plan]);
    final features = <String, dynamic>{};
    for (final row in featureRows) {
      features[row['feature'] as String] = {
        'enabled': (row['enabled'] as int?) == 1,
        'limit':   row['limit_value'] as int? ?? 0,
      };
    }
    if (subRows.isNotEmpty) {
      await db.update(
        'subscription',
        {'shareable_plan_features': jsonEncode(features)},
        where:     'id = ?',
        whereArgs: [subRows.first['id']],
      );
    }
    return features;
  }

  static String _wsPermScopeForPreset(DevicePreset preset) {
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
