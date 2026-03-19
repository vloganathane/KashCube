import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/services/database_helper.dart';

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
          state = state.copyWith(
            state:        WsConnState.connected,
            deviceName:   msg['device_name'] as String?,
            syncedTables: {},
            syncComplete: false,
            errorMsg:     '',
          );
          _pullAllTables();
        case 'AUTH_FAIL':
          state = state.copyWith(
            state:    WsConnState.disconnected,
            errorMsg: 'Authentication failed — scan a new QR code',
          );
          disconnect();
        case 'PING':
          _channel?.sink.add(jsonEncode({'type': 'PONG'}));
        case 'ROWS':
          _handleRows(msg);
        case 'PUSH':
          _handlePush(msg);
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
    debugPrint('[WebSync] PUSH: $table (${rows.length} row(s))');
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
