import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../database_helper.dart';
import '../sync/sync_table_registry.dart';

/// Manages a single browser's WebSocket session.
///
/// Lifecycle:
///   1. [P2pServer] upgrades the `/ws` connection → creates this session.
///   2. Browser sends `{"type":"AUTH","token":"..."}` → [_authenticate].
///   3. Browser pulls tables via `{"type":"PULL","table":"...","since":"..."}`.
///   4. Phone pushes live updates to browser via [pushRows].
///   5. Browser writes via `{"type":"WRITE","table":"...","row":{...}}`.
///   6. On disconnect → [dispose] is called.
class WebBrowserSession {
  WebBrowserSession({
    required this.channel,
    required this.validateToken,
    required this.onWrite,
    required this.schemaVersion,
    required this.deviceName,
  });

  final WebSocketChannel channel;

  /// Validates and consumes the token — returns true if accepted.
  final bool Function(String token) validateToken;

  /// Called when browser writes a row — phone persists it.
  final Future<void> Function(String table, Map<String, dynamic> row) onWrite;

  final int schemaVersion;
  final String deviceName;

  bool _authenticated = false;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  final Map<String, Set<String>> _tableColumnsCache = {};
  final Map<String, SyncTablePlan> _syncPlans = {};

  static const _pingInterval = Duration(seconds: 25);
  Timer? _pingTimer;

  void attach() {
    _sub = channel.stream.listen(
      _onMessage,
      onDone:  dispose,
      onError: (_) => dispose(),
    );
    // Give the browser 10 seconds to authenticate.
    Future<void>.delayed(const Duration(seconds: 10), () {
      if (!_authenticated && !_disposed) {
        _sendRaw({'type': 'AUTH_FAIL', 'reason': 'timeout'});
        dispose();
      }
    });
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final msg  = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = (msg['type'] as String? ?? '').toUpperCase();
      switch (type) {
        case 'AUTH':
          _handleAuth(msg);
          break;
        case 'PULL':
          _handlePull(msg);
          break;
        case 'WRITE':
          _handleWrite(msg);
          break;
        case 'PING':
          _sendRaw({'type': 'PONG'});
          break;
        case 'PONG':
          // Browser keepalive acknowledgment for server-initiated ping.
          break;
        default:
          debugPrint('[WebSession] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[WebSession] Message parse error: $e');
    }
  }

  void _handleAuth(Map<String, dynamic> msg) {
    final token = msg['token'] as String?;
    if (token == null || !validateToken(token)) {
      _sendRaw({'type': 'AUTH_FAIL', 'reason': 'invalid_token'});
      dispose();
      return;
    }
    _authenticated = true;
    _sendRaw({
      'type':           'AUTH_OK',
      'device_name':    deviceName,
      'schema_version': schemaVersion,
    });
    _startPing();
    debugPrint('[WebSession] Browser authenticated');
  }

  Future<void> _handlePull(Map<String, dynamic> msg) async {
    if (!_authenticated) return;
    final table = msg['table'] as String?;
    final since = msg['since'] as String?;
    if (table == null) return;

    try {
      final db  = await DatabaseHelper.instance.database;
      final rows = await _queryRows(db, table, since);

      // Send in batches of 200 to avoid huge single frames.
      const batchSize = 200;
      for (var i = 0; i < rows.length || rows.isEmpty; i += batchSize) {
        final batch    = rows.isEmpty ? <Map<String, dynamic>>[] : rows.sublist(
          i,
          (i + batchSize).clamp(0, rows.length),
        );
        final isFinal = rows.isEmpty || (i + batchSize >= rows.length);
        _sendRaw({
          'type':     'ROWS',
          'table':    table,
          'rows':     batch,
          'is_final': isFinal,
        });
        if (isFinal) break;
      }
    } catch (e) {
      debugPrint('[WebSession] Pull error for $table: $e');
    }
  }

  Future<void> _handleWrite(Map<String, dynamic> msg) async {
    if (!_authenticated) return;
    final table  = msg['table'] as String?;
    final row    = msg['row']   as Map<String, dynamic>?;
    final syncId = msg['sync_id'] as String?;
    if (table == null || row == null) return;

    try {
      await onWrite(table, row);
      _sendRaw({'type': 'WRITE_OK', 'sync_id': syncId});
      // Echo back as PUSH so browser has the canonical row.
      _sendRaw({'type': 'PUSH', 'table': table, 'rows': [row]});
    } catch (e) {
      debugPrint('[WebSession] Write error for $table: $e');
    }
  }

  /// Pushes a live update to the browser (called when phone writes a row).
  void pushRows(String table, List<Map<String, dynamic>> rows) {
    if (!_authenticated || _disposed) return;
    _sendRaw({'type': 'PUSH', 'table': table, 'rows': rows});
  }

  void _sendRaw(Map<String, dynamic> payload) {
    if (_disposed) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[WebSession] Send error: $e');
    }
  }

  void _startPing() {
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (!_disposed) _sendRaw({'type': 'PING'});
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pingTimer?.cancel();
    _sub?.cancel();
    try { channel.sink.close(); } catch (_) {}
    debugPrint('[WebSession] Browser session ended');
  }

  // ── DB helper ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _queryRows(
    Database db,
    String table,
    String? since,
  ) async {
    await _ensureSyncPlans(db);
    if (!_syncPlans.containsKey(table)) {
      debugPrint('[WebSession] Pull rejected for disallowed table: $table');
      return [];
    }

    final columns = await _getTableColumns(db, table);
    final hasUpdatedAt = columns.contains('updated_at');
    final hasDeletedAt = columns.contains('deleted_at');

    final where = <String>[];
    final args = <Object?>[];

    String sqlUtcExpr(String expr) {
      return "CASE WHEN $expr LIKE '%Z' THEN julianday($expr) ELSE julianday($expr, 'utc') END";
    }

    if (since != null && hasUpdatedAt) {
      final tsExpr = sqlUtcExpr('updated_at');
      where.add('$tsExpr > julianday(?)');
      args.add(since);
    }
    if (hasDeletedAt) {
      where.add('deleted_at IS NULL');
    }

    final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    final orderBy = hasUpdatedAt ? ' ORDER BY ${sqlUtcExpr('updated_at')} ASC' : '';
    final sql = 'SELECT * FROM $table$whereSql$orderBy LIMIT 1000';

    try {
      return await db.rawQuery(sql, args);
    } catch (e) {
      debugPrint('[WebSession] Query error on $table: $e');
      return [];
    }
  }

  Future<void> _ensureSyncPlans(Database db) async {
    if (_syncPlans.isNotEmpty) return;

    try {
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
      _syncPlans
        ..clear()
        ..addEntries(plans.map((p) => MapEntry(p.tableName, p)));
    } catch (e) {
      debugPrint('[WebSession] Failed to discover sync plans: $e');
    }
  }

  Future<Set<String>> _getTableColumns(Database db, String table) async {
    final cached = _tableColumnsCache[table];
    if (cached != null) return cached;

    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      final columns = rows
          .map((r) => (r['name'] as String?)?.toLowerCase())
          .whereType<String>()
          .toSet();
      _tableColumnsCache[table] = columns;
      return columns;
    } catch (e) {
      debugPrint('[WebSession] Failed to inspect schema for $table: $e');
      return const <String>{};
    }
  }
}
