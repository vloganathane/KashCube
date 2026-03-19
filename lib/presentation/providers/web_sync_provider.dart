import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/services/database_helper.dart';
import '../../data/services/sync/sync_table_registry.dart';
import '../../data/services/sync_event_bus.dart';

// ── Tables synced from phone on connect ───────────────────────────────────
// Must match the whitelist in WebBrowserSession._queryRows().
const _pullTables = [
  'transactions', 'credits', 'loans', 'parties', 'accounts',
  'categories', 'budgets', 'invoices', 'quotes', 'businesses',
  'purchase_bills', 'item_catalog', 'scheduled_payments',
  'credit_payments',
];

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

  /// True once every table in [_pullTables] has received is_final: true.
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
  final Map<String, DateTime> _outboundLastSentAt = {};
  final Map<String, Set<String>> _tableColumnsCache = {};

  Future<void> connect(String wsUrl, String token) async {
    if (state.state == WsConnState.connecting ||
        state.state == WsConnState.connected) { return; }

    state = state.copyWith(state: WsConnState.connecting);

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone:  _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      // Send AUTH immediately.
      _channel!.sink.add(jsonEncode({'type': 'AUTH', 'token': token}));
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
          final now = DateTime.now().toUtc();
          for (final table in _pullTables) {
            _outboundLastSentAt[table] = now;
          }
          state = state.copyWith(
            state:        WsConnState.connected,
            deviceName:   msg['device_name'] as String?,
            syncedTables: {},
            syncComplete: false,
            errorMsg:     '',
          );
          unawaited(_logDiscoveredSyncPlans());
          _pullAllTables();
          _startWriteLoop();
          break;
        case 'AUTH_FAIL':
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
        default:
          break;
      }
    } catch (e) {
      debugPrint('[WebSync] Message parse error: $e');
    }
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
      final done    = _pullTables.every(updated.contains);
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
      for (final table in _pullTables) {
        final rows = await _queryOutboundRows(
          db: db,
          table: table,
          since: _outboundLastSentAt[table],
        );
        if (rows.isEmpty) {
          continue;
        }

        final normalizedRows = <Map<String, dynamic>>[];
        for (final row in rows) {
          final normalized = Map<String, dynamic>.from(row);
          normalized['sync_id'] ??= _newSyncId();
          _channel?.sink.add(jsonEncode({
            'type': 'WRITE',
            'table': table,
            'sync_id': normalized['sync_id'],
            'row': normalized,
          }));
          normalizedRows.add(normalized);
        }
        _markOutboundWatermarkFromRows(table, normalizedRows);
      }
    } catch (e) {
      debugPrint('[WebSync] Outbound WRITE loop error: $e');
    } finally {
      _writeLoopInFlight = false;
    }
  }

  Future<List<Map<String, dynamic>>> _queryOutboundRows({
    required Database db,
    required String table,
    required DateTime? since,
  }) async {
    final columns = await _getTableColumns(db, table);
    final hasUpdatedAt = columns.contains('updated_at');
    final hasCreatedAt = columns.contains('created_at');
    final hasDeletedAt = columns.contains('deleted_at');

    final where = <String>[];
    final args = <Object?>[];

    String sqlUtcExpr(String expr) {
      return "CASE WHEN $expr LIKE '%Z' THEN julianday($expr) ELSE julianday($expr, 'utc') END";
    }

    if (since != null) {
      final sinceIso = since.toUtc().toIso8601String();
      if (hasUpdatedAt && hasCreatedAt) {
        final tsExpr = sqlUtcExpr('COALESCE(updated_at, created_at)');
        where.add('$tsExpr > julianday(?)');
        args.add(sinceIso);
      } else if (hasUpdatedAt) {
        final tsExpr = sqlUtcExpr('updated_at');
        where.add('$tsExpr > julianday(?)');
        args.add(sinceIso);
      } else if (hasCreatedAt) {
        final tsExpr = sqlUtcExpr('created_at');
        where.add('$tsExpr > julianday(?)');
        args.add(sinceIso);
      }
    }

    if (hasDeletedAt) {
      where.add('deleted_at IS NULL');
    }

    final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    final orderBy = hasUpdatedAt && hasCreatedAt
      ? ' ORDER BY ${sqlUtcExpr('COALESCE(updated_at, created_at)')} ASC'
        : hasUpdatedAt
        ? ' ORDER BY ${sqlUtcExpr('updated_at')} ASC'
            : hasCreatedAt
          ? ' ORDER BY ${sqlUtcExpr('created_at')} ASC'
                : '';
    final sql = 'SELECT * FROM $table$whereSql$orderBy LIMIT 200';
    return db.rawQuery(sql, args);
  }

  Future<Set<String>> _getTableColumns(Database db, String table) async {
    final cached = _tableColumnsCache[table];
    if (cached != null) return cached;

    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final columns = rows
        .map((r) => (r['name'] as String?)?.toLowerCase())
        .whereType<String>()
        .toSet();
    _tableColumnsCache[table] = columns;
    return columns;
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
