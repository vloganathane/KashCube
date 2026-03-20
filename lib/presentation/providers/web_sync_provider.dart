import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/services/database_helper.dart';
import '../../data/services/sync/generic_sync_query_builder.dart';
import '../../data/services/sync/sync_table_registry.dart';
import '../../data/services/sync_event_bus.dart';
import '../web/web_url_reader_stub.dart'
    if (dart.library.js_interop) '../web/web_url_reader_web.dart'
    as url_reader;

// ── WebSocket connection state ─────────────────────────────────────────────

enum WsConnState { disconnected, connecting, connected }

class WebSyncState {
  const WebSyncState({
    this.state        = WsConnState.disconnected,
    this.deviceName,
    this.errorMsg,
    this.syncedTables = const {},
    this.syncComplete = false,
  });
  final WsConnState state;
  final String?     deviceName;
  final String?     errorMsg;

  /// Tables that have received their final ROWS frame from the phone.
  final Set<String> syncedTables;

  /// True once every discovered pull table has received is_final: true.
  final bool syncComplete;

  WebSyncState copyWith({
    WsConnState? state,
    String?      deviceName,
    String?      errorMsg,
    Set<String>? syncedTables,
    bool?        syncComplete,
  }) =>
      WebSyncState(
        state:        state        ?? this.state,
        deviceName:   deviceName   ?? this.deviceName,
        errorMsg:     errorMsg     ?? this.errorMsg,
        syncedTables: syncedTables ?? this.syncedTables,
        syncComplete: syncComplete ?? this.syncComplete,
      );
}

// ── Provider ───────────────────────────────────────────────────────────────

/// Manages the browser-side WebSocket connection to the phone.
/// Only used when running as a Flutter web app inside a browser.
///
/// On AUTH_OK, pulls all whitelisted tables via PULL messages and upserts
/// the resulting ROWS into the in-memory sqflite_common_ffi_web database.
/// PUSH messages (live phone writes) are also upserted incrementally.
/// All existing repositories read from [DatabaseHelper.instance.database]
/// unchanged — zero repo-layer changes required.
class WebSyncNotifier extends StateNotifier<WebSyncState> {
  WebSyncNotifier() : super(const WebSyncState());

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  StreamSubscription<String>? _syncEventSub;
  Timer? _writeTimer;
  bool _writeLoopInFlight = false;
  bool _registrySnapshotLogged = false;
  String? _wsUrl; // remembered for session reconnect logging
  final Map<String, SyncTablePlan> _syncPlans = {};
  final Map<String, DateTime> _outboundLastSentAt = {};
  final Map<String, int>      _outboundLastSentVersion = {};
  final Set<String>           _snapshotSentTables = {};
  Set<String> _pullTables = const <String>{};

  /// Connect with a QR token (first load) or a session token (page refresh).
  ///
  /// Set [isSession] to true when passing a session token instead of a QR
  /// token — the phone will verify it with [SESSION_AUTH] handling.
  Future<void> connect(String wsUrl, String token,
      {bool isSession = false}) async {
    if (state.state == WsConnState.connecting ||
        state.state == WsConnState.connected) { return; }

    state = state.copyWith(state: WsConnState.connecting);
    _wsUrl = wsUrl;

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone:  _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      // Send AUTH or SESSION_AUTH depending on credential type.
      _channel!.sink.add(jsonEncode({
        'type':  isSession ? 'SESSION_AUTH' : 'AUTH',
        'token': token,
      }));
    } catch (e) {
      state = state.copyWith(
        state:    WsConnState.disconnected,
        errorMsg: 'Connection failed: $e',
      );
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg  = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = (msg['type'] as String? ?? '').toUpperCase();
      switch (type) {
        case 'AUTH_OK':
          unawaited(_handleAuthOk(msg));
          break;
        case 'AUTH_FAIL':
          // Clear saved session so the user is prompted to scan a new QR.
          url_reader.clearSession();
          state = state.copyWith(
            state:    WsConnState.disconnected,
            errorMsg: 'Authentication failed — scan a new QR code',
          );
          disconnect();
          break;
        case 'PING':
          _channel?.sink.add(jsonEncode({'type': 'PONG'}));
          break;
        case 'PONG':
          // Keepalive acknowledgment for browser-initiated ping (if enabled).
          break;
        case 'ROWS':
          _handleRows(msg);
          break;
        case 'PUSH':
          _handlePush(msg);
          break;
        case 'WRITE_OK':
          break;
        case 'SYNC_PLAN':
          _handleSyncPlan(msg);
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('[WebSync] Message parse error: $e');
    }
  }

  Future<void> _handleAuthOk(Map<String, dynamic> msg) async {
    // Persist session token so a page refresh can re-authenticate without
    // requiring a new QR scan.  The phone rotates the session_id on every
    // successful auth, so we always save the freshest value.
    final sessionId = msg['session_id'] as String?;
    if (sessionId != null && _wsUrl != null) {
      url_reader.saveSession(sessionId, _wsUrl!);
    }

    await _logDiscoveredSyncPlans();

    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();
    _snapshotSentTables.clear();
    final now = DateTime.now().toUtc();
    for (final plan in _outboundTables()) {
      switch (plan.mode) {
        case SyncMode.deltaTs:
          _outboundLastSentAt[plan.tableName] = now;
        case SyncMode.snapshot:
          // Never echo snapshot rows back to the phone — phone is authoritative.
          _snapshotSentTables.add(plan.tableName);
        case SyncMode.deltaVersion:
          // First flush will send from version 0; acceptable for infrequent tables.
          break;
      }
    }

    state = state.copyWith(
      state:        WsConnState.connected,
      deviceName:   msg['device_name'] as String?,
      syncedTables: {},
      syncComplete: _pullTables.isEmpty,
      errorMsg:     '',
    );

    _pullAllTables();
    _startWriteLoop();
  }

  /// Sends PULL requests for all whitelisted tables after AUTH_OK.
  /// No `since` filter — in-memory DB starts empty on every browser load.
  void _pullAllTables() {
    for (final table in _pullTables) {
      _channel?.sink.add(jsonEncode({'type': 'PULL', 'table': table}));
    }
  }

  Future<void> _logDiscoveredSyncPlans() async {
    if (_registrySnapshotLogged) return;
    _registrySnapshotLogged = true;
    try {
      final db = await DatabaseHelper.instance.database;
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
      _syncPlans
        ..clear()
        ..addEntries(plans.map((p) => MapEntry(p.tableName, p)));
      // Only pull tables the browser is eligible to receive.
      _pullTables = plans
          .where((p) => p.isWebEligible)
          .map((p) => p.tableName)
          .toSet();
      final deltaTs = plans.where((p) => p.mode == SyncMode.deltaTs).length;
      final deltaVersion =
          plans.where((p) => p.mode == SyncMode.deltaVersion).length;
      final snapshot = plans.where((p) => p.mode == SyncMode.snapshot).length;

      debugPrint(
        '[SyncRegistry][Web] discovered=${plans.length} delta_ts=$deltaTs delta_version=$deltaVersion snapshot=$snapshot',
      );
    } catch (e) {
      debugPrint('[SyncRegistry][Web] discovery failed: $e');
    }
  }

  /// Handles a ROWS frame: upserts rows into in-memory SQLite, marks the
  /// table done when is_final is true. Emits syncComplete when all tables
  /// have received their final frame.
  Future<void> _handleRows(Map<String, dynamic> msg) async {
    final table   = msg['table']    as String?;
    final rows    = msg['rows']     as List<dynamic>?;
    final isFinal = msg['is_final'] as bool? ?? false;

    if (table == null || rows == null) return;

    if (rows.isNotEmpty) {
      await _upsertRows(table, rows);
      _markOutboundWatermarkFromRows(table, rows);
      DatabaseHelper.instance.notifyChange(table);
    }

    if (isFinal) {
      final updated = {...state.syncedTables, table};
      final done = _pullTables.every(updated.contains);
      state = state.copyWith(
        syncedTables: updated,
        syncComplete: done,
      );
      debugPrint('[WebSync] Table synced: $table (all done: $done)');
    }
  }

  /// Handles a PUSH frame (live phone write): upserts rows incrementally.
  Future<void> _handlePush(Map<String, dynamic> msg) async {
    final table = msg['table'] as String?;
    final rows  = msg['rows']  as List<dynamic>?;
    if (table == null || rows == null || rows.isEmpty) return;
    await _upsertRows(table, rows);
    _markOutboundWatermarkFromRows(table, rows);
    DatabaseHelper.instance.notifyChange(table);
    debugPrint('[WebSync] PUSH: $table (${rows.length} row(s))');
  }

  /// Handles the phone's SYNC_PLAN message: logs the advertised tables so
  /// we can verify alignment with the browser's own discovery.
  void _handleSyncPlan(Map<String, dynamic> msg) {
    final tables = msg['tables'] as List<dynamic>? ?? [];
    debugPrint('[WebSync] Phone SYNC_PLAN: ${tables.length} table(s)');
    for (final entry in tables) {
      if (entry is Map<String, dynamic>) {
        final name = entry['name'] as String? ?? '?';
        final mode = entry['mode'] as String? ?? '?';
        debugPrint('[WebSync]   ↳ $name ($mode)');
      }
    }
  }

  void _startWriteLoop() {
    _writeTimer?.cancel();
    _writeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _flushLocalWritesToPhone();
    });
    // Trigger immediately whenever a local table changes.
    _syncEventSub?.cancel();
    _syncEventSub = SyncEventBus.instance.stream.listen((table) {
      _flushLocalWritesToPhone();
    });
  }

  Future<void> _flushLocalWritesToPhone() async {
    if (_writeLoopInFlight) {
      return;
    }
    if (state.state != WsConnState.connected || _channel == null) {
      return;
    }
    _writeLoopInFlight = true;

    try {
      final db = await DatabaseHelper.instance.database;
      for (final plan in _outboundTables()) {
        final table = plan.tableName;
        if (plan.mode == SyncMode.snapshot && _snapshotSentTables.contains(table)) {
          continue;
        }

        final query = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: plan,
          since: plan.mode == SyncMode.deltaTs ? _outboundLastSentAt[table] : null,
          afterVersion: plan.mode == SyncMode.deltaVersion
              ? _outboundLastSentVersion[table]
              : null,
        );
        final rows = await db.rawQuery(query.sql, query.args);
        if (rows.isEmpty) continue;

        for (final row in rows) {
          final normalized = Map<String, dynamic>.from(row);
          normalized['sync_id'] ??= _newSyncId();
          _channel?.sink.add(jsonEncode({
            'type': 'WRITE',
            'table': table,
            'sync_id': normalized['sync_id'],
            'row': normalized,
          }));
        }

        // Advance watermark after successful push.
        switch (plan.mode) {
          case SyncMode.deltaTs:
            _outboundLastSentAt[table] = GenericSyncQueryBuilder.maxTimestamp(rows);
          case SyncMode.deltaVersion:
            final maxV = GenericSyncQueryBuilder.maxVersion(rows);
            if (maxV != null) _outboundLastSentVersion[table] = maxV;
          case SyncMode.snapshot:
            _snapshotSentTables.add(table);
        }
      }
    } catch (e) {
      debugPrint('[WebSync] Outbound WRITE loop error: $e');
    } finally {
      _writeLoopInFlight = false;
    }
  }

  List<SyncTablePlan> _outboundTables() {
    return _syncPlans.values
        .where((plan) => plan.isWebEligible)
        .toList()
      ..sort((a, b) => a.tableName.compareTo(b.tableName));
  }

  void _markOutboundWatermarkFromRows(String table, List<dynamic> rows) {
    if (rows.isEmpty) return;
    var maxTs = _outboundLastSentAt[table] ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    for (final row in rows) {
      if (row is! Map) continue;
      final map = row;
      final updatedRaw = map['updated_at']?.toString();
      final createdRaw = map['created_at']?.toString();
      final ts = DateTime.tryParse(updatedRaw ?? '') ??
          DateTime.tryParse(createdRaw ?? '');
      if (ts != null && ts.toUtc().isAfter(maxTs)) {
        maxTs = ts.toUtc();
      }
    }

    _outboundLastSentAt[table] = maxTs;
  }

  String _newSyncId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    return '${now.toRadixString(16)}$rand';
  }

  /// Bulk-upserts [rows] into the in-memory SQLite using INSERT OR REPLACE.
  Future<void> _upsertRows(String table, List<dynamic> rows) async {
    try {
      final db    = await DatabaseHelper.instance.database;
      final batch = db.batch();
      for (final r in rows) {
        if (r is Map<String, dynamic>) {
          batch.insert(
            table,
            r,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[WebSync] Upsert error for $table: $e');
    }
  }

  void _onDisconnected() {
    state = state.copyWith(
      state:      WsConnState.disconnected,
      deviceName: null,
    );
  }

  void disconnect() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _syncEventSub?.cancel();
    _syncEventSub = null;
    _syncPlans.clear();
    _pullTables = const <String>{};
    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();
    _snapshotSentTables.clear();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _onDisconnected();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

final webSyncProvider =
    StateNotifierProvider<WebSyncNotifier, WebSyncState>(
  (_) => WebSyncNotifier(),
);
