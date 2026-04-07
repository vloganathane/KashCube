import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/sync_repository.dart';
import '../services/database_helper.dart';
import '../services/sync/sync_table_registry.dart';

/// WebRTC-based implementation of [SyncRepository].
///
/// Uses WebSocket (browser ↔ phone) or WebRTC DataChannel (future) for transport.
/// This is the current sync implementation, extracted from WebSyncNotifier.
///
/// **Architecture** (Phase 0):
/// - Transport ownership: WebSyncNotifier (presentation layer) owns SyncTransportChannel
/// - Message handling: Repository exposes handleXxxMessage() methods
/// - Send callback: Repository calls _sendMessage() to request frame transmission
///
/// **Future** (Phase 1+):
/// - Repository will own the transport directly
/// - WebSyncNotifier will become a thin state-only wrapper
///
/// **Protocol**: JSON frames (ROWS, PUSH, WRITE_OK, SYNC_PLAN)
/// **Conflict resolution**: Last-Write-Wins (REPLACE conflict algorithm)
///
/// **Status**: Work in progress (Phase 0, Task 5)
class WebRTCSyncRepositoryImpl implements SyncRepository {
  WebRTCSyncRepositoryImpl({
    DatabaseHelper? dbHelper,
    int inboundDedupeCapacity = 512,
    void Function(Map<String, dynamic>)? sendMessage,
    void Function(String)? notifyTableChanged,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _inboundDedupeCapacity = inboundDedupeCapacity,
        _sendMessage = sendMessage,
        _notifyTableChanged = notifyTableChanged;

  final DatabaseHelper _dbHelper;
  final int _inboundDedupeCapacity;
  final void Function(Map<String, dynamic>)? _sendMessage;
  final void Function(String)? _notifyTableChanged;
  final StreamController<SyncConnectionState> _connectionStateController =
      StreamController<SyncConnectionState>.broadcast();
  final StreamController<List<SyncPeer>> _peersController =
      StreamController<List<SyncPeer>>.broadcast();
  final StreamController<SyncEvent> _eventsController =
      StreamController<SyncEvent>.broadcast();

  SyncConnectionState _currentState = SyncConnectionState.disconnected;
  String? _connectedPeerId;
  final Set<String> _completedTables = {};
  final Set<String> _pendingTables = {};
  int _rowsSynced = 0;

  // Inbound deduplication: bounded LRU cache per table (prevents memory leak)
  final Map<String, Set<String>> _seenInboundRowIdsByTable = {};
  final Map<String, ListQueue<String>> _seenInboundRowOrderByTable = {};

  // Outbound watermarks (for delta sync)
  final Map<String, DateTime> _outboundLastSentAt = {};
  final Map<String, int> _outboundLastSentVersion = {};

  // ── Connection Lifecycle ────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    // TODO: Load identity, prepare WebSocket/WebRTC resources
    _emitState(SyncConnectionState.disconnected);
  }

  @override
  Future<void> connect({required String peerId}) async {
    if (_currentState == SyncConnectionState.connected ||
        _currentState == SyncConnectionState.connecting) {
      return; // Already connected/connecting
    }

    _connectedPeerId = peerId;
    _emitState(SyncConnectionState.connecting);

    try {
      // TODO: Establish WebSocket or WebRTC connection
      // For now, simulate connection (actual logic in WebSyncNotifier)
      
      _emitState(SyncConnectionState.connected);
      _eventsController.add(const SyncStarted());
    } catch (e, stack) {
      _emitState(SyncConnectionState.error);
      _eventsController.add(SyncError(
        message: 'Connection failed',
        error: e,
        stackTrace: stack,
      ));
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_currentState == SyncConnectionState.disconnected) return;

    // TODO: Close WebSocket/WebRTC connection
    
    _connectedPeerId = null;
    _completedTables.clear();
    _pendingTables.clear();
    _rowsSynced = 0;
    
    _emitState(SyncConnectionState.disconnected);
    _eventsController.add(const SyncDisconnected(reason: 'User disconnect'));
  }

  @override
  Stream<SyncConnectionState> get connectionState =>
      _connectionStateController.stream;

  void _emitState(SyncConnectionState newState) {
    _currentState = newState;
    _connectionStateController.add(newState);
  }

  // ── Discovery ───────────────────────────────────────────────────────────

  @override
  Stream<List<SyncPeer>> discoverPeers() {
    // WebRTC (web) doesn't support mDNS discovery
    // Pairing happens via QR code instead
    // Emit empty list immediately
    _peersController.add([]);
    return _peersController.stream;
  }

  @override
  Future<void> stopDiscovery() async {
    // No-op for WebRTC (no active discovery)
  }

  // ── Sync Operations ─────────────────────────────────────────────────────

  @override
  Future<void> syncTable(String tableName) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Call connect() first.');
    }

    _emitState(SyncConnectionState.syncing);
    _pendingTables.add(tableName);

    try {
      // TODO: Implement pull request (PULL message)
      // For now, this is a placeholder — WebSyncNotifier still handles PULL/ROWS flow
      
      // Simulate sync completion
      await Future.delayed(const Duration(milliseconds: 100));
      
      _completedTables.add(tableName);
      _pendingTables.remove(tableName);
      
      _eventsController.add(SyncTableCompleted(
        tableName: tableName,
        rowsProcessed: 0, // TODO: Track actual count
      ));

      if (_pendingTables.isEmpty) {
        _emitState(SyncConnectionState.connected);
      }
    } catch (e, stack) {
      _emitState(SyncConnectionState.error);
      _eventsController.add(SyncError(
        message: 'Sync failed for table $tableName',
        error: e,
        stackTrace: stack,
      ));
      rethrow;
    }
  }

  @override
  Future<void> syncAllTables() async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Call connect() first.');
    }

    final db = await _dbHelper.database;
    final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
    
    _completedTables.clear();
    _rowsSynced = 0;
    final startTime = DateTime.now();

    for (final plan in plans) {
      await syncTable(plan.tableName);
    }

    final duration = DateTime.now().difference(startTime);
    _eventsController.add(SyncCompleted(
      totalRowsSynced: _rowsSynced,
      duration: duration,
    ));
  }

  @override
  Future<SyncProgress> getSyncProgress() async {
    return SyncProgress(
      completedTables: Set.from(_completedTables),
      pendingTables: Set.from(_pendingTables),
      rowsSynced: _rowsSynced,
      rowsPending: 0, // TODO: Calculate based on watermarks
    );
  }

  // ── Message Handlers (called by WebSyncNotifier) ───────────────────────

  /// Handles ROWS frame (snapshot/delta sync).
  ///
  /// **Design**: Extracted from WebSyncNotifier._handleRows() (line 837).
  /// **Protocol**: { "type": "ROWS", "table": "...", "rows": [...], "is_final": true/false }
  Future<void> handleRowsMessage(Map<String, dynamic> msg) async {
    final table = msg['table'] as String?;
    final rows = msg['rows'] as List<dynamic>?;
    final isFinal = msg['is_final'] as bool? ?? false;

    if (table == null || rows == null) {
      debugPrint('[WebRTCSync] Malformed ROWS message (missing table or rows)');
      return;
    }

    final filteredRows = _filterNewInboundRows(table, rows);

    if (filteredRows.isNotEmpty) {
      await _upsertRows(table, filteredRows);
      _markOutboundWatermarkFromRows(table, filteredRows);
      _rowsSynced += filteredRows.length;

      // Notify DatabaseHelper to broadcast change
      final hook = _notifyTableChanged;
      if (hook != null) {
        hook(table);
      } else {
        _dbHelper.notifyChange(table);
      }
    }

    if (isFinal) {
      _completedTables.add(table);
      _eventsController.add(SyncTableCompleted(
        tableName: table,
        rowsProcessed: filteredRows.length,
      ));

      debugPrint('[WebRTCSync] Table synced: $table (${filteredRows.length} rows)');

      // Check if all pending tables are done
      if (_pendingTables.isNotEmpty && _pendingTables.every(_completedTables.contains)) {
        _pendingTables.clear();
        _emitState(SyncConnectionState.connected);
        
        _eventsController.add(SyncCompleted(
          totalRowsSynced: _rowsSynced,
          duration: Duration.zero, // TODO: Track sync start time
        ));
      }
    }
  }

  /// Handles PUSH frame (live incremental write from phone).
  ///
  /// **Design**: Extracted from WebSyncNotifier._handlePush() (line 867).
  /// **Protocol**: { "type": "PUSH", "table": "...", "rows": [...] }
  Future<void> handlePushMessage(Map<String, dynamic> msg) async {
    final table = msg['table'] as String?;
    final rows = msg['rows'] as List<dynamic>?;

    if (table == null || rows == null || rows.isEmpty) {
      debugPrint('[WebRTCSync] Malformed PUSH message');
      return;
    }

    final filteredRows = _filterNewInboundRows(table, rows);

    if (filteredRows.isEmpty) {
      debugPrint('[WebRTCSync] PUSH deduped: $table (${rows.length} duplicate row(s))');
      return;
    }

    await _upsertRows(table, filteredRows);
    _markOutboundWatermarkFromRows(table, filteredRows);
    _rowsSynced += filteredRows.length;

    // Notify DatabaseHelper to broadcast change
    final hook = _notifyTableChanged;
    if (hook != null) {
      hook(table);
    } else {
      _dbHelper.notifyChange(table);
    }

    debugPrint('[WebRTCSync] PUSH: $table (${filteredRows.length} row(s))');
  }

  /// Handles SYNC_PLAN frame (phone's advertised tables).
  ///
  /// **Design**: Extracted from WebSyncNotifier._handleSyncPlan() (line 914).
  /// Logs the remote registry for debugging alignment.
  void handleSyncPlanMessage(Map<String, dynamic> msg) {
    final tables = msg['tables'] as List<dynamic>? ?? [];
    debugPrint('[WebRTCSync] Phone SYNC_PLAN: ${tables.length} table(s)');
    for (final entry in tables) {
      if (entry is Map<String, dynamic>) {
        final name = entry['name'] as String? ?? '?';
        final mode = entry['mode'] as String? ?? '?';
        debugPrint('[WebRTCSync]   ↳ $name ($mode)');
      }
    }
  }

  // ── Real-time Push ──────────────────────────────────────────────────────

  @override
  Future<void> pushRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Cannot push row.');
    }

    final sendHook = _sendMessage;
    if (sendHook == null) {
      throw StateError('No send callback configured');
    }

    sendHook({
      'type': 'PUSH',
      'table': table,
      'rows': [row], // Single row as 1-element array
    });
  }

  @override
  Future<void> pushRows({
    required String table,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Cannot push rows.');
    }

    final sendHook = _sendMessage;
    if (sendHook == null) {
      throw StateError('No send callback configured');
    }

    sendHook({
      'type': 'PUSH',
      'table': table,
      'rows': rows,
    });
  }

  // ── Events ──────────────────────────────────────────────────────────────

  @override
  Stream<SyncEvent> get events => _eventsController.stream;

  // ── Deduplication ───────────────────────────────────────────────────────

  /// Filters out rows that were already seen (by sync_id).
  ///
  /// Uses a bounded LRU cache per table to prevent memory leaks. When the cache
  /// reaches [_inboundDedupeCapacity], the oldest entries are evicted.
  ///
  /// **Design**: Extracted from WebSyncNotifier._filterNewInboundRows() (line 893).
  /// See [PHASE_0_FOUNDATION_STATUS.md] Task 2 for deduplication strategy.
  List<dynamic> _filterNewInboundRows(String table, List<dynamic> rows) {
    final seenIds = _seenInboundRowIdsByTable.putIfAbsent(
      table,
      () => <String>{},
    );
    final seenOrder = _seenInboundRowOrderByTable.putIfAbsent(
      table,
      () => ListQueue<String>(),
    );

    final filtered = <dynamic>[];
    for (final row in rows) {
      if (row is! Map) {
        filtered.add(row); // Malformed row, pass through
        continue;
      }

      final syncId = row['sync_id']?.toString();
      if (syncId == null || syncId.isEmpty) {
        filtered.add(row); // No sync_id (shouldn't happen), pass through
        continue;
      }

      if (seenIds.contains(syncId)) {
        // Already processed
        continue;
      }

      // Add to cache
      seenIds.add(syncId);
      seenOrder.addLast(syncId);

      // Evict oldest entry if capacity exceeded (LRU eviction)
      while (seenOrder.length > _inboundDedupeCapacity) {
        final evicted = seenOrder.removeFirst();
        seenIds.remove(evicted);
      }

      filtered.add(row);
    }

    return filtered;
  }

  // ── Database Merge ──────────────────────────────────────────────────────

  /// Merges remote rows into local database using REPLACE conflict resolution.
  ///
  /// **Design**: Extracted from WebSyncNotifier._upsertRows() (line 1120).
  /// Uses PRAGMA table_info to filter out invalid columns (prevents SQL errors).
  Future<void> _upsertRows(String table, List<dynamic> rows) async {
    try {
      final db = await _dbHelper.database;
      final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
      final validCols = tableInfo.map((r) => r['name'] as String).toSet();

      final batch = db.batch();
      for (final r in rows) {
        if (r is Map<String, dynamic>) {
          // Filter out columns that don't exist in schema
          final filtered = Map<String, dynamic>.fromEntries(
            r.entries.where((e) => validCols.contains(e.key)),
          );
          if (filtered.isNotEmpty) {
            batch.insert(
              table,
              filtered,
              conflictAlgorithm: ConflictAlgorithm.replace, // Last-Write-Wins
            );
          }
        }
      }
      await batch.commit(noResult: true);
    } catch (e, stack) {
      debugPrint('[WebRTCSync] Upsert error for $table: $e');
      // Don't rethrow — partial failure shouldn't block entire sync
    }
  }

  /// Updates outbound watermark based on inbound rows (prevents echo).
  ///
  /// **Design**: Extracted from WebSyncNotifier._markOutboundWatermarkFromRows() (line 1078).
  /// Ensures we don't re-send rows we just received.
  void _markOutboundWatermarkFromRows(String table, List<dynamic> rows) {
    if (rows.isEmpty) return;

    var maxTs = _outboundLastSentAt[table] ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    for (final row in rows) {
      if (row is! Map) continue;
      final map = row;
      final updatedRaw = map['updated_at']?.toString();
      final createdRaw = map['created_at']?.toString();

      if (updatedRaw != null) {
        final ts = DateTime.tryParse(updatedRaw);
        if (ts != null && ts.isAfter(maxTs)) {
          maxTs = ts;
        }
      }
      if (createdRaw != null) {
        final ts = DateTime.tryParse(createdRaw);
        if (ts != null && ts.isAfter(maxTs)) {
          maxTs = ts;
        }
      }
    }

    _outboundLastSentAt[table] = maxTs;
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  void dispose() {
    _connectionStateController.close();
    _peersController.close();
    _eventsController.close();
    _seenInboundRowIdsByTable.clear();
    _seenInboundRowOrderByTable.clear();
    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();
  }
}
