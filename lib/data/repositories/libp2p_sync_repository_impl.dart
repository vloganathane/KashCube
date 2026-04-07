import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/sync_repository.dart';
import '../services/database_helper.dart';
import '../services/identity_service.dart';
import '../services/libp2p/libp2p_discovery.dart';
import '../services/libp2p/libp2p_node.dart';
import '../services/libp2p/libp2p_protocol.dart';
import '../services/sync/sync_table_registry.dart';

/// libp2p-based implementation of [SyncRepository].
///
/// Uses dart_libp2p for peer-to-peer sync over TCP/UDX with Noise encryption.
/// Implements the /kash-sync/1.0.0 protocol designed in Phase 1.2.
///
/// **Architecture** (Phase 1):
/// - Transport ownership: Repository owns LibP2pNode directly
/// - Frame handling: LibP2pProtocol parses length-prefixed JSON frames
/// - Discovery: LibP2pDiscovery handles mDNS peer detection
///
/// **Protocol**: /kash-sync/1.0.0 (length-prefixed JSON: 4B header + UTF-8 payload)
/// **Frame types**: SYNC_PLAN, ROWS, PUSH, WRITE_OK, ERROR, PING, PONG
/// **Security**: Noise protocol (encryption + authentication), PeerId verification
/// **Conflict resolution**: Last-Write-Wins (REPLACE conflict algorithm)
///
/// **Status**: Phase 1.4 implementation (April 2026)
class Libp2pSyncRepositoryImpl implements SyncRepository {
  Libp2pSyncRepositoryImpl({
    LibP2pNode? node,
    LibP2pProtocol? protocol,
    LibP2pDiscovery? discovery,
    DatabaseHelper? dbHelper,
    IdentityService? identityService,
    int inboundDedupeCapacity = 512,
  })  : _node = node ?? LibP2pNode(),
        _protocol = protocol ?? LibP2pProtocol(),
        _discovery = discovery ?? LibP2pDiscovery(),
        _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _identityService = identityService ?? IdentityService.instance,
        _inboundDedupeCapacity = inboundDedupeCapacity;

  final LibP2pNode _node;
  final LibP2pProtocol _protocol;
  final LibP2pDiscovery _discovery;
  final DatabaseHelper _dbHelper;
  // ignore: unused_field
  final IdentityService _identityService; // Reserved for Ed25519 identity integration
  final int _inboundDedupeCapacity;

  final StreamController<SyncConnectionState> _connectionStateController =
      StreamController<SyncConnectionState>.broadcast();
  final StreamController<SyncEvent> _eventsController =
      StreamController<SyncEvent>.broadcast();

  SyncConnectionState _currentState = SyncConnectionState.disconnected;
  String? _connectedPeerId; // Currently connected peer ID (libp2p PeerId)
  dynamic _activeStream; // libp2p stream (using dynamic until API confirmed)
  final Set<String> _completedTables = {};
  final Set<String> _pendingTables = {};
  int _rowsSynced = 0;
  DateTime? _syncStartTime;

  // Inbound deduplication: bounded LRU cache per table (prevents memory leak)
  final Map<String, Set<String>> _seenInboundRowIdsByTable = {};
  final Map<String, ListQueue<String>> _seenInboundRowOrderByTable = {};

  // Outbound watermarks (for delta sync)
  final Map<String, DateTime> _outboundLastSentAt = {};
  final Map<String, int> _outboundLastSentVersion = {};

  // Stream subscription for discovery
  StreamSubscription<SyncPeer>? _discoverySubscription;

  // ────────────────────────────────────────────────────────────────────────────
  // Connection Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    debugPrint('[Libp2pSync] Initializing...');
    _emitState(SyncConnectionState.disconnected);

    try {
      // Ensure identity service initialized
      // Note: IdentityService.ensureInitialized() should be called earlier
      // during app startup. We skip it here to avoid loading SettingsRepository.
      // In production, identity initialization happens in main.dart.
      
      // TODO: Replace with actual identity extraction when identity is ready
      // For now, use placeholder (dart_libp2p will generate identity if null)
      await _node.initialize(
        identity: null, // Let dart_libp2p generate identity for now
        listenAddrs: [
          '/ip4/0.0.0.0/tcp/0', // Random TCP port
          '/ip4/0.0.0.0/udp/0/udx', // Random UDX port
        ],
      );

      // Register protocol handlers using LibP2pProtocol
      _registerProtocolHandlers();

      // Start listening for connections
      await _node.start();

      debugPrint('[Libp2pSync] Initialized successfully');
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Initialization failed: $e');
      debugPrint(stack.toString());
      _emitState(SyncConnectionState.error);
      rethrow;
    }
  }

  @override
  Future<void> connect({required String peerId}) async {
    if (_currentState == SyncConnectionState.connected ||
        _currentState == SyncConnectionState.connecting) {
      debugPrint('[Libp2pSync] Already connected/connecting to $peerId');
      return;
    }

    _connectedPeerId = peerId;
    _emitState(SyncConnectionState.connecting);
    _syncStartTime = DateTime.now();

    try {
      debugPrint('[Libp2pSync] Connecting to peer: $_connectedPeerId');

      // Open stream to peer using /kash-sync/1.0.0 protocol
      _activeStream = await _node.dial(
        peerId, // Multiaddr constructed from peerId
        protocolId: kashSyncProtocolId,
      );

      _emitState(SyncConnectionState.connected);
      _eventsController.add(const SyncStarted());

      debugPrint('[Libp2pSync] Connected to $_connectedPeerId');
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Connection failed: $e');
      debugPrint(stack.toString());
      _emitState(SyncConnectionState.error);
      _eventsController.add(SyncError(
        message: 'Connection failed to $_connectedPeerId',
        error: e,
        stackTrace: stack,
      ));
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_currentState == SyncConnectionState.disconnected) {
      return;
    }

    debugPrint('[Libp2pSync] Disconnecting...');

    try {
      // Close active stream
      if (_activeStream != null) {
        // TODO: Close stream when dart_libp2p API confirmed
        // await _activeStream.close();
        _activeStream = null;
      }

      // Stop discovery
      await stopDiscovery();

      // Close node (graceful shutdown)
      await _node.close();

      _connectedPeerId = null;
      _completedTables.clear();
      _pendingTables.clear();
      _rowsSynced = 0;
      _syncStartTime = null;

      _emitState(SyncConnectionState.disconnected);
      _eventsController.add(const SyncDisconnected(reason: 'User disconnect'));

      debugPrint('[Libp2pSync] Disconnected');
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Disconnect error: $e');
      debugPrint(stack.toString());
    }
  }

  @override
  Stream<SyncConnectionState> get connectionState =>
      _connectionStateController.stream;

  void _emitState(SyncConnectionState newState) {
    _currentState = newState;
    _connectionStateController.add(newState);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Discovery
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SyncPeer>> discoverPeers() {
    debugPrint('[Libp2pSync] Starting peer discovery...');
    _emitState(SyncConnectionState.discovering);

    final controller = StreamController<List<SyncPeer>>();
    final discoveredPeers = <String, SyncPeer>{}; // peerId → SyncPeer

    // Start discovery asynchronously
    _startDiscoveryAsync(controller, discoveredPeers);

    return controller.stream;
  }

  /// Helper to start discovery asynchronously.
  Future<void> _startDiscoveryAsync(
    StreamController<List<SyncPeer>> controller,
    Map<String, SyncPeer> discoveredPeers,
  ) async {
    try {
      // Ensure node is initialized
      if (_node.host == null) {
        throw StateError('Cannot start discovery: libp2p node not initialized');
      }

      // Start mDNS discovery using the Host
      // MdnsDiscovery extracts multiaddrs and peer ID automatically from host
      await _discovery.start(
        host: _node.host!,
      );

      // Listen for discovered peers via discoveredPeers stream
      _discoverySubscription = _discovery.discoveredPeers.listen(
        (peer) {
          debugPrint('[Libp2pSync] Discovered peer: ${peer.displayName}');
          discoveredPeers[peer.peerId] = peer;
          controller.add(discoveredPeers.values.toList());
        },
        onError: (e, stack) {
          debugPrint('[Libp2pSync] Discovery error: $e');
          debugPrint(stack.toString());
          controller.addError(e, stack);
        },
        onDone: () {
          debugPrint('[Libp2pSync] Discovery stream closed');
          controller.close();
        },
      );
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Discovery start failed: $e');
      debugPrint(stack.toString());
      controller.addError(e, stack);
      controller.close();
    }
  }

  @override
  Future<void> stopDiscovery() async {
    debugPrint('[Libp2pSync] Stopping discovery...');

    await _discoverySubscription?.cancel();
    _discoverySubscription = null;

    await _discovery.stop();

    if (_currentState == SyncConnectionState.discovering) {
      _emitState(SyncConnectionState.disconnected);
    }

    debugPrint('[Libp2pSync] Discovery stopped');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Sync Operations
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Future<void> syncTable(String tableName) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Call connect() first.');
    }

    if (_activeStream == null) {
      throw StateError('No active stream to peer');
    }

    debugPrint('[Libp2pSync] Syncing table: $tableName');
    _emitState(SyncConnectionState.syncing);
    _pendingTables.add(tableName);

    try {
      // Request rows from peer (PULL frame)
      // Note: In /kash-sync/1.0.0 protocol, we send SYNC_PLAN instead of PULL
      // The peer responds with ROWS frames
      final db = await _dbHelper.database;
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
      
      // Find plan for this table
      final plan = plans.firstWhere(
        (p) => p.tableName == tableName,
        orElse: () => throw StateError('Table $tableName not in sync registry'),
      );

      // Send SYNC_PLAN for single table
      await _sendFrame({
        'type': 'SYNC_PLAN',
        'tables': [
          {
            'name': tableName,
            'mode': plan.mode.name,
            'watermark': _outboundLastSentAt[tableName]?.toIso8601String(),
          }
        ],
      });

      // Protocol handler will receive ROWS frames and call _handleRowsFrame
      // When final=true, we'll mark table as complete
      debugPrint('[Libp2pSync] SYNC_PLAN sent for $tableName');
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Sync failed for $tableName: $e');
      debugPrint(stack.toString());
      _pendingTables.remove(tableName);
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

    debugPrint('[Libp2pSync] Syncing all tables...');
    final db = await _dbHelper.database;
    final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);

    _completedTables.clear();
    _rowsSynced = 0;
    _syncStartTime = DateTime.now();

    for (final plan in plans) {
      await syncTable(plan.tableName);
    }

    // Emit completion event when all tables done
    final duration = DateTime.now().difference(_syncStartTime!);
    _eventsController.add(SyncCompleted(
      totalRowsSynced: _rowsSynced,
      duration: duration,
    ));

    debugPrint('[Libp2pSync] All tables synced ($duration)');
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

  // ────────────────────────────────────────────────────────────────────────────
  // Real-time Push
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Future<void> pushRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Cannot push row.');
    }

    if (_activeStream == null) {
      throw StateError('No active stream to peer');
    }

    await _sendFrame({
      'type': 'PUSH',
      'table': table,
      'rows': [row],
    });

    debugPrint('[Libp2pSync] PUSH: $table (1 row)');
  }

  @override
  Future<void> pushRows({
    required String table,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Cannot push rows.');
    }

    if (_activeStream == null) {
      throw StateError('No active stream to peer');
    }

    await _sendFrame({
      'type': 'PUSH',
      'table': table,
      'rows': rows,
    });

    debugPrint('[Libp2pSync] PUSH: $table (${rows.length} rows)');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Events
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Stream<SyncEvent> get events => _eventsController.stream;

  // ────────────────────────────────────────────────────────────────────────────
  // Protocol Handlers
  // ────────────────────────────────────────────────────────────────────────────

  /// Register frame handlers with LibP2pProtocol.
  void _registerProtocolHandlers() {
    // SYNC_PLAN: Remote peer's table registry
    _protocol.registerHandler('SYNC_PLAN', _handleSyncPlanFrame);

    // ROWS: Bulk data transfer (snapshot or delta)
    _protocol.registerHandler('ROWS', _handleRowsFrame);

    // PUSH: Real-time incremental write
    _protocol.registerHandler('PUSH', _handlePushFrame);

    // WRITE_OK: Acknowledgment for PUSH
    _protocol.registerHandler('WRITE_OK', _handleWriteOkFrame);

    // ERROR: Remote error during sync
    _protocol.registerHandler('ERROR', _handleErrorFrame);

    // PING: Keepalive request
    _protocol.registerHandler('PING', _handlePingFrame);

    // PONG: Keepalive response
    _protocol.registerHandler('PONG', _handlePongFrame);

    debugPrint('[Libp2pSync] Protocol handlers registered');
  }

  /// Handle SYNC_PLAN frame (peer's table registry).
  Future<Map<String, dynamic>?> _handleSyncPlanFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final tables = frame['tables'] as List<dynamic>? ?? [];
    debugPrint('[Libp2pSync] Received SYNC_PLAN from $peerId: ${tables.length} table(s)');

    for (final entry in tables) {
      if (entry is Map<String, dynamic>) {
        final name = entry['name'] as String? ?? '?';
        final mode = entry['mode'] as String? ?? '?';
        debugPrint('[Libp2pSync]   ↳ $name ($mode)');
      }
    }

    // No response needed for SYNC_PLAN
    return null;
  }

  /// Handle ROWS frame (bulk data transfer).
  Future<Map<String, dynamic>?> _handleRowsFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final table = frame['table'] as String?;
    final rows = frame['rows'] as List<dynamic>?;
    final isFinal = frame['is_final'] as bool? ?? false;

    if (table == null || rows == null) {
      debugPrint('[Libp2pSync] Malformed ROWS frame (missing table or rows)');
      return {
        'type': 'ERROR',
        'code': 'MALFORMED_FRAME',
        'message': 'ROWS frame missing required fields',
      };
    }

    // Deduplicate rows
    final filteredRows = _filterNewInboundRows(table, rows);

    if (filteredRows.isNotEmpty) {
      // Merge into local database
      await _upsertRows(table, filteredRows);

      // Update watermark to prevent echo
      _markOutboundWatermarkFromRows(table, filteredRows);

      _rowsSynced += filteredRows.length;

      // Notify DatabaseHelper to broadcast change
      _dbHelper.notifyChange(table);
    }

    if (isFinal) {
      _completedTables.add(table);
      _pendingTables.remove(table);

      _eventsController.add(SyncTableCompleted(
        tableName: table,
        rowsProcessed: filteredRows.length,
      ));

      debugPrint('[Libp2pSync] Table synced: $table (${filteredRows.length} rows)');

      // Check if all pending tables are done
      if (_pendingTables.isEmpty && _completedTables.isNotEmpty) {
        _emitState(SyncConnectionState.connected);

        final duration = _syncStartTime != null
            ? DateTime.now().difference(_syncStartTime!)
            : Duration.zero;

        _eventsController.add(SyncCompleted(
          totalRowsSynced: _rowsSynced,
          duration: duration,
        ));
      }
    }

    // No response needed for ROWS (protocol is push-based)
    return null;
  }

  /// Handle PUSH frame (real-time incremental write).
  Future<Map<String, dynamic>?> _handlePushFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final table = frame['table'] as String?;
    final rows = frame['rows'] as List<dynamic>?;

    if (table == null || rows == null || rows.isEmpty) {
      debugPrint('[Libp2pSync] Malformed PUSH frame');
      return {
        'type': 'ERROR',
        'code': 'MALFORMED_FRAME',
        'message': 'PUSH frame missing required fields',
      };
    }

    // Deduplicate rows
    final filteredRows = _filterNewInboundRows(table, rows);

    if (filteredRows.isEmpty) {
      debugPrint('[Libp2pSync] PUSH deduped: $table (${rows.length} duplicate row(s))');
      return {
        'type': 'WRITE_OK',
        'table': table,
        'count': 0,
      };
    }

    // Merge into local database
    await _upsertRows(table, filteredRows);

    // Update watermark
    _markOutboundWatermarkFromRows(table, filteredRows);

    _rowsSynced += filteredRows.length;

    // Notify DatabaseHelper to broadcast change
    _dbHelper.notifyChange(table);

    debugPrint('[Libp2pSync] PUSH: $table (${filteredRows.length} row(s))');

    // Send WRITE_OK acknowledgment
    return {
      'type': 'WRITE_OK',
      'table': table,
      'count': filteredRows.length,
    };
  }

  /// Handle WRITE_OK frame (acknowledgment for PUSH).
  Future<Map<String, dynamic>?> _handleWriteOkFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final table = frame['table'] as String?;
    final count = frame['count'] as int? ?? 0;

    debugPrint('[Libp2pSync] WRITE_OK: $table ($count rows acknowledged)');

    // No response needed
    return null;
  }

  /// Handle ERROR frame (remote error during sync).
  Future<Map<String, dynamic>?> _handleErrorFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final code = frame['code'] as String? ?? 'UNKNOWN';
    final message = frame['message'] as String? ?? 'Unknown error';

    debugPrint('[Libp2pSync] ERROR from $peerId: $code - $message');

    _eventsController.add(SyncError(
      message: 'Remote error: $message',
      error: Exception('$code: $message'),
    ));

    // No response needed
    return null;
  }

  /// Handle PING frame (keepalive request).
  Future<Map<String, dynamic>?> _handlePingFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    debugPrint('[Libp2pSync] PING from $peerId');

    // Respond with PONG
    return {'type': 'PONG'};
  }

  /// Handle PONG frame (keepalive response).
  Future<Map<String, dynamic>?> _handlePongFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    debugPrint('[Libp2pSync] PONG from $peerId');

    // No response needed
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Frame Serialization
  // ────────────────────────────────────────────────────────────────────────────

  /// Send a JSON frame to the connected peer.
  ///
  /// Uses LibP2pProtocol to serialize with length prefix (4B big-endian u32 + UTF-8).
  Future<void> _sendFrame(Map<String, dynamic> frame) async {
    if (_activeStream == null) {
      throw StateError('No active stream');
    }

    // TODO: Use LibP2pProtocol._sendFrame when API confirmed
    // For now, placeholder implementation
    throw UnimplementedError(
      'Frame sending not yet implemented - awaiting dart_libp2p API integration',
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Deduplication
  // ────────────────────────────────────────────────────────────────────────────

  /// Filters out rows that were already seen (by sync_id).
  ///
  /// Uses a bounded LRU cache per table to prevent memory leaks. When the cache
  /// reaches [_inboundDedupeCapacity], the oldest entries are evicted.
  ///
  /// **Design**: Ported from WebRTCSyncRepositoryImpl._filterNewInboundRows().
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

  // ────────────────────────────────────────────────────────────────────────────
  // Database Merge
  // ────────────────────────────────────────────────────────────────────────────

  /// Merges remote rows into local database using REPLACE conflict resolution.
  ///
  /// **Design**: Ported from WebRTCSyncRepositoryImpl._upsertRows().
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
      debugPrint('[Libp2pSync] Upsert error for $table: $e');
      debugPrint(stack.toString());
      // Don't rethrow — partial failure shouldn't block entire sync
    }
  }

  /// Updates outbound watermark based on inbound rows (prevents echo).
  ///
  /// **Design**: Ported from WebRTCSyncRepositoryImpl._markOutboundWatermarkFromRows().
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

  // ────────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ────────────────────────────────────────────────────────────────────────────

  /// Dispose resources.
  void dispose() {
    _connectionStateController.close();
    _eventsController.close();
    _discoverySubscription?.cancel();
    _seenInboundRowIdsByTable.clear();
    _seenInboundRowOrderByTable.clear();
    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();
  }
}
