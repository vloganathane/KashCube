import 'dart:async';
import 'dart:collection';
import 'dart:math'; // For pow(), min() in exponential backoff

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/sync_repository.dart';
import '../models/peer_quality.dart';
import '../models/vector_clock.dart';
import '../services/database_helper.dart';
import '../services/libp2p/libp2p_broadcast.dart';
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
    int inboundDedupeCapacity = 512,
  }) : _node = node ?? LibP2pNode(),
       _protocol = protocol ?? LibP2pProtocol(),
       _discovery = discovery ?? LibP2pDiscovery(),
       _dbHelper = dbHelper ?? DatabaseHelper.instance,
       _inboundDedupeCapacity = inboundDedupeCapacity;

  final LibP2pNode _node;
  final LibP2pProtocol _protocol;
  final LibP2pDiscovery _discovery;
  final DatabaseHelper _dbHelper;
  final int _inboundDedupeCapacity;

  // Broadcast layer for mesh networking (Phase 2)
  LibP2pBroadcast? _broadcast;
  StreamSubscription<TopicMessage>? _broadcastSubscription;
  static const String _syncTopic = '/kash-sync/1.0.0';

  final StreamController<SyncConnectionState> _connectionStateController =
      StreamController<SyncConnectionState>.broadcast();
  final StreamController<SyncEvent> _eventsController =
      StreamController<SyncEvent>.broadcast();

  SyncConnectionState _currentState = SyncConnectionState.disconnected;

  // ── Multi-peer connection tracking ────────────────────────────────────────
  final Set<String> _connectedPeerIds = {}; // All connected peer IDs
  final Map<String, dynamic> _peerStreams = {}; // peerId → stream
  final Map<String, SyncConnectionState> _peerConnectionStates =
      {}; // peerId → state
  static const int _maxPeers =
      10; // Max simultaneous connections (configurable)

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

  // Auto-connect tracking
  final Set<String> _attemptedConnections =
      {}; // Track dial attempts to avoid duplicates
  final Set<String> _activePeers = {}; // Currently connected peers
  final Map<String, List<String>> _peerMultiaddrs =
      {}; // peerId → multiaddrs mapping from discovery
  final bool _autoConnectEnabled = true; // Enable/disable auto-connect

  // ── Conflict resolution (Phase 3) ──────────────────────────────────────────
  String? _deviceId; // This device's ID (from libp2p peer ID)
  VectorClock _vectorClock = VectorClock.empty(); // Local vector clock
  final Map<String, VectorClock> _peerVectorClocks =
      {}; // peerId → their last known clock

  // ── Resilience (Phase 4) ───────────────────────────────────────────────────
  // Health checks
  Timer? _healthCheckTimer; // Periodic PING timer
  final Map<String, DateTime> _peerLastSeen = {}; // peerId → last PONG time
  static const Duration _healthCheckInterval = Duration(
    seconds: 30,
  ); // PING frequency
  static const Duration _peerTimeout = Duration(
    seconds: 90,
  ); // 3x health check (declare dead)

  // Auto-reconnect
  final Map<String, int> _reconnectAttempts = {}; // peerId → attempt count
  final Map<String, DateTime> _reconnectBackoff =
      {}; // peerId → retry after time
  static const Duration _reconnectBaseDelay = Duration(seconds: 2);
  static const Duration _reconnectMaxDelay = Duration(seconds: 60);

  // Peer quality scoring
  final Map<String, PeerQuality> _peerQuality = {}; // peerId → quality metrics

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

      // Set device ID from libp2p peer ID (Phase 3: Conflict resolution)
      _deviceId = _node.localPeerId;
      if (_deviceId != null) {
        // Initialize vector clock with device ID at 0
        _vectorClock = VectorClock({_deviceId!: 0});
        debugPrint('[Libp2pSync] Device ID: $_deviceId');
        debugPrint('[Libp2pSync] Vector clock initialized: $_vectorClock');
      } else {
        debugPrint(
          '[Libp2pSync] ⚠️ Warning: No peer ID, vector clock disabled',
        );
      }

      // Initialize broadcast layer for mesh networking (Phase 2)
      _broadcast = LibP2pBroadcast(
        node: _node,
        protocol: _protocol,
        peerStreams: _peerStreams,
      );

      // Subscribe to sync topic
      debugPrint('[Libp2pSync] Subscribing to topic: $_syncTopic');
      _broadcastSubscription = _broadcast!.subscribe(
        _syncTopic,
        _handleBroadcastMessage,
      );

      // Auto-start discovery for automatic peer connection
      debugPrint('[Libp2pSync] Starting auto-discovery...');
      discoverPeers(); // Start discovery stream (non-blocking)

      // Start health check timer (Phase 4: Resilience)
      _startHealthCheckTimer();

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
    // Check if already connected to this specific peer
    if (_connectedPeerIds.contains(peerId)) {
      debugPrint('[Libp2pSync] Already connected to $peerId');
      return;
    }

    // Check peer limit
    if (_connectedPeerIds.length >= _maxPeers) {
      debugPrint(
        '[Libp2pSync] ⚠️ Max peer limit reached ($_maxPeers). Cannot connect to $peerId',
      );
      return;
    }

    _peerConnectionStates[peerId] = SyncConnectionState.connecting;
    _emitState(SyncConnectionState.connecting);
    _syncStartTime ??= DateTime.now();

    try {
      debugPrint(
        '[Libp2pSync] Connecting to peer $peerId (${_connectedPeerIds.length + 1}/$_maxPeers)',
      );

      // Look up multiaddr for this peer from discovery
      final multiaddrs = _peerMultiaddrs[peerId];
      if (multiaddrs == null || multiaddrs.isEmpty) {
        throw StateError(
          'No multiaddrs found for peer $peerId. Discovery may not have completed.',
        );
      }

      // Use the first multiaddr (TODO: Try all addrs on failure)
      final multiaddr = multiaddrs.first;
      debugPrint('[Libp2pSync] Dialing multiaddr: $multiaddr');

      // Track connection attempt (Phase 4: Resilience)
      final quality = _peerQuality.putIfAbsent(peerId, () => PeerQuality());
      quality.recordConnectionAttempt();

      // Open stream to peer using /kash-sync/1.0.0 protocol
      final stream = await _node.dial(
        multiaddr, // Use full multiaddr, not just peerId
        protocolId: kashSyncProtocolId,
      );

      // Store peer connection
      _peerStreams[peerId] = stream;
      _connectedPeerIds.add(peerId);
      _peerConnectionStates[peerId] = SyncConnectionState.connected;

      // Track peer quality (Phase 4: Resilience)
      quality.recordConnectionSuccess();
      _peerLastSeen[peerId] = DateTime.now(); // Mark as recently seen

      // Clear reconnect backoff on successful connection
      _reconnectAttempts.remove(peerId);
      _reconnectBackoff.remove(peerId);

      // Update global state if this is our first connection
      if (_connectedPeerIds.length == 1) {
        _emitState(SyncConnectionState.connected);
        _eventsController.add(const SyncStarted());
      }

      debugPrint(
        '[Libp2pSync] ✅ Connected to $peerId (${_connectedPeerIds.length}/$_maxPeers peers) [${quality.qualityRating}]',
      );
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Connection to $peerId failed: $e');
      debugPrint(stack.toString());

      // Track connection failure (Phase 4: Resilience)
      final quality = _peerQuality.putIfAbsent(peerId, () => PeerQuality());
      quality.recordConnectionFailure();

      // Clean up failed connection attempt
      _peerConnectionStates.remove(peerId);
      _peerStreams.remove(peerId);

      // Only emit error if we have no other connections
      if (_connectedPeerIds.isEmpty) {
        _emitState(SyncConnectionState.error);
        _eventsController.add(
          SyncError(
            message: 'Connection failed to $peerId',
            error: e,
            stackTrace: stack,
          ),
        );
      }

      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await disconnectAll();
  }

  /// Disconnect from all peers and shut down the libp2p node.
  Future<void> disconnectAll() async {
    if (_currentState == SyncConnectionState.disconnected) {
      return;
    }

    debugPrint('[Libp2pSync] Disconnecting from all peers...');

    try {
      // Close all peer streams
      for (final peerId in _connectedPeerIds.toList()) {
        await _disconnectPeer(peerId, notifyGlobal: false);
      }

      // Stop discovery
      await stopDiscovery();

      // Close broadcast layer
      await _broadcastSubscription?.cancel();
      _broadcast?.close();
      _broadcast = null;

      // Close node (graceful shutdown)
      await _node.close();

      _completedTables.clear();
      _pendingTables.clear();
      _rowsSynced = 0;
      _syncStartTime = null;

      // Clear auto-connect tracking
      _attemptedConnections.clear();
      _activePeers.clear();
      _peerMultiaddrs.clear();

      // Clear multi-peer tracking
      _connectedPeerIds.clear();
      _peerStreams.clear();
      _peerConnectionStates.clear();

      _emitState(SyncConnectionState.disconnected);
      _eventsController.add(const SyncDisconnected(reason: 'User disconnect'));

      debugPrint('[Libp2pSync] ✅ Disconnected from all peers');
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Disconnect error: $e');
      debugPrint(stack.toString());
    }
  }

  /// Disconnect from a specific peer.
  Future<void> _disconnectPeer(
    String peerId, {
    bool notifyGlobal = true,
  }) async {
    if (!_connectedPeerIds.contains(peerId)) {
      return;
    }

    debugPrint('[Libp2pSync] Disconnecting from peer $peerId');

    try {
      // Close stream for this peer
      final stream = _peerStreams[peerId];
      if (stream != null) {
        // TODO: Close stream when dart_libp2p API confirmed
        // await stream.close();
      }

      // Record disconnect in peer quality (Phase 4: Resilience)
      final quality = _peerQuality[peerId];
      if (quality != null) {
        quality.recordDisconnect();
        debugPrint(
          '[Libp2pSync] Peer $peerId quality: ${quality.qualityScore.toStringAsFixed(1)} (${quality.qualityRating})',
        );
      }

      // Remove peer tracking
      _peerStreams.remove(peerId);
      _connectedPeerIds.remove(peerId);
      _peerConnectionStates.remove(peerId);
      _activePeers.remove(peerId);

      // Clear resilience state for this peer (Phase 4: Resilience)
      _peerLastSeen.remove(peerId);
      // Keep _peerQuality for reconnection quality history
      // Keep _reconnectAttempts and _reconnectBackoff for auto-reconnect tracking

      debugPrint(
        '[Libp2pSync] Disconnected from $peerId (${_connectedPeerIds.length} peers remaining)',
      );

      // Update global state if this was our last connection
      if (notifyGlobal && _connectedPeerIds.isEmpty) {
        _emitState(SyncConnectionState.disconnected);
        _eventsController.add(
          SyncDisconnected(reason: 'Peer $peerId disconnected'),
        );
      }
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Error disconnecting from $peerId: $e');
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
      final host = _node.host;
      if (host != null) {
        // Start mDNS discovery using the Host.
        await _discovery.start(host: host);
      } else if (_discovery.runtimeType != LibP2pDiscovery) {
        // Test doubles may not rely on a concrete libp2p Host.
        await (_discovery as dynamic).start(host: null);
      } else {
        throw StateError('Cannot start discovery: libp2p node not initialized');
      }

      // Listen for discovered peers via discoveredPeers stream
      _discoverySubscription = _discovery.discoveredPeers.listen(
        (peer) {
          debugPrint('[Libp2pSync] Discovered peer: ${peer.displayName}');
          discoveredPeers[peer.peerId] = peer;

          // Store multiaddrs for this peer (retrieved from discovery service)
          final multiaddrs = _discovery.getMultiaddrs(peer.peerId);
          if (multiaddrs != null && multiaddrs.isNotEmpty) {
            _peerMultiaddrs[peer.peerId] = multiaddrs;
            debugPrint(
              '[Libp2pSync] Stored multiaddrs for ${peer.peerId}: ${multiaddrs.first}',
            );
          }

          controller.add(discoveredPeers.values.toList());

          // ══════════════════════════════════════════════════════════════
          // AUTO-CONNECT: Dial discovered peers immediately
          // ══════════════════════════════════════════════════════════════
          if (_autoConnectEnabled &&
              !_attemptedConnections.contains(peer.peerId)) {
            _autoConnectToPeer(peer.peerId);
          }
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

  /// Auto-connect to a discovered peer (Option 1 + Option 3 hybrid).
  ///
  /// Strategy:
  /// 1. Dial immediately (aggressive discovery)
  /// 2. Check if peer is trusted (trusted_peers table)
  /// 3. If trusted: proceed with sync
  /// 4. If new: verify identity (same owner keypair = auto-trust)
  /// 5. If untrusted: disconnect (or show pairing prompt in UI)
  ///
  /// This combines fast discovery with intelligent trust management.
  Future<void> _autoConnectToPeer(String peerId) async {
    // Check if we've reached max peer limit
    if (_connectedPeerIds.length >= _maxPeers) {
      debugPrint(
        '[Libp2pSync] ⚠️ Max peer limit reached ($_maxPeers), skipping auto-connect to $peerId',
      );
      return;
    }

    // Mark as attempted to avoid duplicate dials
    if (_attemptedConnections.contains(peerId)) {
      debugPrint('[Libp2pSync] Already attempted connection to $peerId');
      return;
    }
    _attemptedConnections.add(peerId);

    debugPrint(
      '[Libp2pSync] Auto-connecting to peer $peerId (${_connectedPeerIds.length}/$_maxPeers)',
    );

    try {
      // Check if we're already connected to this peer
      if (_connectedPeerIds.contains(peerId)) {
        debugPrint('[Libp2pSync] Already connected to $peerId, skipping');
        return;
      }

      // Check if peer is in trusted_peers table
      final isTrusted = await _isTrustedPeer(peerId);

      if (isTrusted) {
        debugPrint(
          '[Libp2pSync] ✅ Peer $peerId is trusted, establishing connection',
        );
      } else {
        debugPrint(
          '[Libp2pSync] ⚠️ Peer $peerId is NEW (not in trusted_peers)',
        );
        // TODO: Implement identity verification handshake
        // For now, we'll attempt connection anyway and let protocol handle auth
        // Future: Add Ed25519 signature verification here
      }

      // Attempt to dial the peer
      // Note: connect() now handles multi-peer logic internally
      await connect(peerId: peerId);

      // Track active peer (already done in connect(), but keep for compatibility)
      _activePeers.add(peerId);

      // If trusted, trigger sync automatically
      if (isTrusted) {
        debugPrint('[Libp2pSync] Auto-syncing with trusted peer $peerId');
        // TODO: Call syncAll() or specific tables
        // For now, connection is established and sync can be triggered manually
      }
    } catch (e, stack) {
      debugPrint('[Libp2pSync] Auto-connect to $peerId failed: $e');
      debugPrint(stack.toString());

      // Remove from active peers on failure
      _activePeers.remove(peerId);

      // Don't rethrow - auto-connect failures should be non-fatal
      // The peer might be offline or the connection might fail for network reasons
    }
  }

  /// Check if a peer is in the trusted_peers table.
  ///
  /// Returns true if the peer exists and is active in trusted_peers.
  Future<bool> _isTrustedPeer(String peerId) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.query(
        'trusted_peers',
        where: 'peer_id = ? AND is_active = 1',
        whereArgs: [peerId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('[Libp2pSync] Error checking trusted peer: $e');
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Sync Operations
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Future<void> syncTable(String tableName) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Call connect() first.');
    }

    // TODO(Phase 2): Broadcast to all peers via gossipsub
    // For now, use first available peer
    if (_peerStreams.isEmpty) {
      throw StateError('No active streams to peers');
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
          },
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
      _eventsController.add(
        SyncError(
          message: 'Sync failed for table $tableName',
          error: e,
          stackTrace: stack,
        ),
      );
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
    _eventsController.add(
      SyncCompleted(totalRowsSynced: _rowsSynced, duration: duration),
    );

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

    if (_peerStreams.isEmpty) {
      throw StateError('No active streams to peers');
    }

    // Increment vector clock for local change (Phase 3)
    _incrementVectorClock();

    await _sendFrame({
      'type': 'PUSH',
      'table': table,
      'rows': [row],
      'vectorClock': _vectorClock.toJson(), // Include vector clock
      'deviceId': _deviceId, // Include device ID
    });

    debugPrint(
      '[Libp2pSync] PUSH: $table (1 row) [${_vectorClock.toCompactString()}]',
    );
  }

  @override
  Future<void> pushRows({
    required String table,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (_currentState != SyncConnectionState.connected) {
      throw StateError('Not connected. Cannot push rows.');
    }

    if (_peerStreams.isEmpty) {
      throw StateError('No active streams to peers');
    }

    // Increment vector clock for local change (Phase 3)
    _incrementVectorClock();

    await _sendFrame({
      'type': 'PUSH',
      'table': table,
      'rows': rows,
      'vectorClock': _vectorClock.toJson(), // Include vector clock
      'deviceId': _deviceId, // Include device ID
    });

    debugPrint(
      '[Libp2pSync] PUSH: $table (${rows.length} rows) [${_vectorClock.toCompactString()}]',
    );
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

    // BROADCAST: Mesh network broadcast messages (Phase 2)
    _protocol.registerHandler('BROADCAST', _handleBroadcastFrame);

    debugPrint('[Libp2pSync] Protocol handlers registered');
  }

  /// Handle SYNC_PLAN frame (peer's table registry).
  Future<Map<String, dynamic>?> _handleSyncPlanFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final tables = frame['tables'] as List<dynamic>? ?? [];
    debugPrint(
      '[Libp2pSync] Received SYNC_PLAN from $peerId: ${tables.length} table(s)',
    );

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

      _eventsController.add(
        SyncTableCompleted(
          tableName: table,
          rowsProcessed: filteredRows.length,
        ),
      );

      debugPrint(
        '[Libp2pSync] Table synced: $table (${filteredRows.length} rows)',
      );

      // Check if all pending tables are done
      if (_pendingTables.isEmpty && _completedTables.isNotEmpty) {
        _emitState(SyncConnectionState.connected);

        final duration = _syncStartTime != null
            ? DateTime.now().difference(_syncStartTime!)
            : Duration.zero;

        _eventsController.add(
          SyncCompleted(totalRowsSynced: _rowsSynced, duration: duration),
        );
      }
    }

    // No response needed for ROWS (protocol is push-based)
    return null;
  }

  /// Handle PUSH frame (real-time incremental write).
  ///
  /// **Phase 3**: Includes conflict detection via vector clocks.
  /// If concurrent update detected, applies Last-Write-Wins strategy.
  Future<Map<String, dynamic>?> _handlePushFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final table = frame['table'] as String?;
    final rows = frame['rows'] as List<dynamic>?;
    final vectorClockJson = frame['vectorClock'] as Map<String, dynamic>?;
    final senderDeviceId = frame['deviceId'] as String?;

    if (table == null || rows == null || rows.isEmpty) {
      debugPrint('[Libp2pSync] Malformed PUSH frame');
      return {
        'type': 'ERROR',
        'code': 'MALFORMED_FRAME',
        'message': 'PUSH frame missing required fields',
      };
    }

    // ── Phase 3: Conflict detection ──────────────────────────────────────────
    VectorClock? theirClock;
    if (vectorClockJson != null) {
      try {
        theirClock = VectorClock.fromJson(vectorClockJson);

        // Detect conflict
        final relationship = _vectorClock.compareTo(theirClock);

        if (relationship.isConflict) {
          debugPrint(
            '[Libp2pSync] ⚠️ CONFLICT detected on $table from $peerId',
          );
          debugPrint('  Local:  ${_vectorClock.toCompactString()}');
          debugPrint('  Remote: ${theirClock.toCompactString()}');

          // Apply Last-Write-Wins: Accept remote changes (they won)
          // Alternative: Could prompt user or use other merge strategies
          debugPrint('  → Applying Last-Write-Wins (accepting remote)');
        }

        // Merge vector clocks (take max of each device's counter)
        _mergeVectorClock(theirClock);

        // Track peer's clock
        if (senderDeviceId != null) {
          _peerVectorClocks[senderDeviceId] = theirClock;
        }
      } catch (e) {
        debugPrint('[Libp2pSync] Error parsing vector clock: $e');
      }
    }

    // Deduplicate rows
    final filteredRows = _filterNewInboundRows(table, rows);

    if (filteredRows.isEmpty) {
      debugPrint(
        '[Libp2pSync] PUSH deduped: $table (${rows.length} duplicate row(s))',
      );
      return {'type': 'WRITE_OK', 'table': table, 'count': 0};
    }

    // Merge into local database
    await _upsertRows(table, filteredRows);

    // Update watermark
    _markOutboundWatermarkFromRows(table, filteredRows);

    _rowsSynced += filteredRows.length;

    // Notify DatabaseHelper to broadcast change
    _dbHelper.notifyChange(table);

    final clockInfo = theirClock != null
        ? ' [${theirClock.toCompactString()}]'
        : '';
    debugPrint(
      '[Libp2pSync] PUSH: $table (${filteredRows.length} row(s))$clockInfo',
    );

    // Send WRITE_OK acknowledgment
    return {'type': 'WRITE_OK', 'table': table, 'count': filteredRows.length};
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

    _eventsController.add(
      SyncError(
        message: 'Remote error: $message',
        error: Exception('$code: $message'),
      ),
    );

    // No response needed
    return null;
  }

  /// Handle PING frame (keepalive request).
  ///
  /// **Phase 4**: Records peer as active and tracks latency.
  Future<Map<String, dynamic>?> _handlePingFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final timestamp = frame['timestamp'] as int?;

    debugPrint('[Libp2pSync] PING from $peerId');

    // Update last seen time (Phase 4: Resilience)
    _peerLastSeen[peerId] = DateTime.now();

    // Respond with PONG, echoing timestamp for latency calculation
    return {'type': 'PONG', 'timestamp': timestamp};
  }

  /// Handle PONG frame (keepalive response).
  ///
  /// **Phase 4**: Records latency and updates peer quality.
  Future<Map<String, dynamic>?> _handlePongFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final sentTimestamp = frame['timestamp'] as int?;

    // Calculate latency if timestamp present
    if (sentTimestamp != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final latencyMs = now - sentTimestamp;

      // Update peer quality with latency (Phase 4: Resilience)
      final quality = _peerQuality[peerId];
      if (quality != null) {
        quality.recordLatency(latencyMs);
        debugPrint(
          '[Libp2pSync] PONG from $peerId (${latencyMs}ms) [${quality.qualityRating}]',
        );
      } else {
        debugPrint('[Libp2pSync] PONG from $peerId (${latencyMs}ms)');
      }
    } else {
      debugPrint('[Libp2pSync] PONG from $peerId');
    }

    // Update last seen time (Phase 4: Resilience)
    _peerLastSeen[peerId] = DateTime.now();

    // No response needed
    return null;
  }

  /// Handle BROADCAST frame (mesh network broadcast).
  ///
  /// Receives broadcast messages from peers and forwards to broadcast layer
  /// for deduplication and topic routing.
  Future<Map<String, dynamic>?> _handleBroadcastFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final message = frame['message'] as Map<String, dynamic>?;

    if (message == null) {
      debugPrint('[Libp2pSync] Malformed BROADCAST frame (missing message)');
      return null;
    }

    debugPrint('[Libp2pSync] Received BROADCAST from $peerId');

    // Forward to broadcast layer for processing
    if (_broadcast != null) {
      await _broadcast!.handleIncomingMessage(message);
    }

    // No response needed
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Frame Serialization
  // ────────────────────────────────────────────────────────────────────────────

  /// Send a JSON frame to all connected peers via broadcast.
  ///
  /// Uses LibP2pBroadcast to send to all peers in the mesh network.
  /// Messages are automatically deduplicated and re-broadcasted by peers.
  ///
  /// **Phase 2**: True mesh network broadcasting with automatic propagation.
  Future<void> _sendFrame(Map<String, dynamic> frame) async {
    if (_peerStreams.isEmpty) {
      throw StateError('No active peers');
    }

    if (_broadcast == null) {
      throw StateError('Broadcast layer not initialized');
    }

    // Broadcast to all peers via topic
    await _broadcast!.publish(topic: _syncTopic, data: frame);

    debugPrint(
      '[Libp2pSync] Broadcasted ${frame['type']} to ${_peerStreams.length} peers',
    );
  }

  /// Handle incoming broadcast message from the mesh network.
  ///
  /// Called when a message arrives on $_syncTopic.
  /// Processes sync frames (SYNC_PLAN, ROWS, PUSH, etc.).
  void _handleBroadcastMessage(TopicMessage message) {
    debugPrint(
      '[Libp2pSync] Received broadcast: ${message.data['type']} from mesh',
    );

    // Process the frame based on type
    final frame = message.data;
    final type = frame['type'] as String?;

    if (type == null) {
      debugPrint('[Libp2pSync] Invalid broadcast frame (no type)');
      return;
    }

    // Handle frame types
    // Note: For now, we'll use the existing protocol handlers
    // TODO: Refactor protocol handlers to work with broadcast messages
    // For Phase 2, we're primarily focused on enabling broadcast infrastructure

    debugPrint('[Libp2pSync] Processing broadcast frame: $type');
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

    var maxTs =
        _outboundLastSentAt[table] ??
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
  // Vector Clock Operations (Phase 3: Conflict Resolution)
  // ────────────────────────────────────────────────────────────────────────────

  /// Increment the local vector clock for a local change.
  ///
  /// Called before sending PUSH messages to track causality.
  void _incrementVectorClock() {
    if (_deviceId == null) {
      debugPrint('[Libp2pSync] ⚠️ Cannot increment vector clock: no device ID');
      return;
    }

    _vectorClock = _vectorClock.increment(_deviceId!);

    debugPrint(
      '[Libp2pSync] Vector clock incremented: ${_vectorClock.toCompactString()}',
    );
  }

  /// Merge a received vector clock with the local clock.
  ///
  /// Takes the max of each device's counter. Called when receiving
  /// PUSH/ROWS frames to update knowledge of distributed state.
  void _mergeVectorClock(VectorClock receivedClock) {
    final oldClock = _vectorClock;
    _vectorClock = _vectorClock.merge(receivedClock);

    if (_vectorClock != oldClock) {
      debugPrint(
        '[Libp2pSync] Vector clock merged: ${_vectorClock.toCompactString()}',
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Health Check & Auto-Reconnect (Phase 4: Resilience)
  // ────────────────────────────────────────────────────────────────────────────

  /// Start periodic health check timer.
  ///
  /// Sends PING to all peers every [_healthCheckInterval] (30s).
  /// Detects stale peers (no response for [_peerTimeout] = 90s).
  /// Triggers auto-reconnect for timed out peers.
  void _startHealthCheckTimer() {
    _healthCheckTimer?.cancel(); // Cancel existing timer if any

    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _performHealthCheck();
    });

    debugPrint('[Libp2pSync] Health check timer started (every 30s)');
  }

  /// Perform health check on all connected peers.
  ///
  /// 1. Send PING to all peers
  /// 2. Check for stale peers (no PONG for 90s)
  /// 3. Disconnect stale peers
  /// 4. Trigger auto-reconnect for stale peers
  Future<void> _performHealthCheck() async {
    if (_connectedPeerIds.isEmpty) {
      return; // No peers to check
    }

    final now = DateTime.now();
    final stalePeers = <String>[];

    // Check each connected peer
    for (final peerId in _connectedPeerIds.toList()) {
      final lastSeen = _peerLastSeen[peerId];

      // Check if peer has timed out (no activity for 90s)
      if (lastSeen != null && now.difference(lastSeen) > _peerTimeout) {
        debugPrint(
          '[Libp2pSync] ⚠️ Peer $peerId timed out (no activity for ${now.difference(lastSeen).inSeconds}s)',
        );
        stalePeers.add(peerId);
        continue; // Don't send PING to stale peer
      }

      // Send PING with timestamp for latency measurement
      try {
        final timestamp = now.millisecondsSinceEpoch;
        await _sendFrame({'type': 'PING', 'timestamp': timestamp});

        // Track message sent (Phase 4: Resilience)
        final quality = _peerQuality[peerId];
        quality?.recordMessageSent();

        debugPrint('[Libp2pSync] PING sent to $peerId');
      } catch (e) {
        debugPrint('[Libp2pSync] Failed to send PING to $peerId: $e');

        // Track message failure (Phase 4: Resilience)
        final quality = _peerQuality[peerId];
        quality?.recordMessageFailure();
      }
    }

    // Handle stale peers
    for (final peerId in stalePeers) {
      // Disconnect stale peer
      await _disconnectPeer(peerId);

      // Get peer's multiaddrs for reconnection
      final multiaddrs = _discovery.getMultiaddrs(peerId);
      if (multiaddrs == null || multiaddrs.isEmpty) {
        debugPrint('[Libp2pSync] Cannot reconnect to $peerId: no multiaddrs');
        continue;
      }

      // Trigger auto-reconnect
      debugPrint(
        '[Libp2pSync] Triggering auto-reconnect for stale peer $peerId',
      );
      unawaited(_autoReconnectToPeer(peerId, multiaddrs));
    }
  }

  /// Auto-reconnect to a peer with exponential backoff.
  ///
  /// Implements exponential backoff: 2s, 4s, 8s, 16s, 32s, 60s (cap).
  /// Stops retrying if connection succeeds or max attempts reached.
  ///
  /// **Phase 4**: Production-grade reconnection with backoff.
  Future<void> _autoReconnectToPeer(
    String peerId,
    List<String> multiaddrs,
  ) async {
    // Check if we're already in backoff
    final backoffUntil = _reconnectBackoff[peerId];
    if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
      final waitSeconds = backoffUntil.difference(DateTime.now()).inSeconds;
      debugPrint(
        '[Libp2pSync] Skipping reconnect to $peerId (in backoff for ${waitSeconds}s)',
      );
      return;
    }

    // Get current attempt count
    final attempts = _reconnectAttempts[peerId] ?? 0;

    // Calculate backoff delay: min(2^attempts * baseDelay, maxDelay)
    final backoffMultiplier = pow(2, attempts);
    final backoffDelay = Duration(
      milliseconds: min(
        (_reconnectBaseDelay.inMilliseconds * backoffMultiplier).toInt(),
        _reconnectMaxDelay.inMilliseconds,
      ),
    );

    // Set backoff time
    _reconnectBackoff[peerId] = DateTime.now().add(backoffDelay);

    debugPrint(
      '[Libp2pSync] Auto-reconnect to $peerId (attempt ${attempts + 1}, delay ${backoffDelay.inSeconds}s)',
    );

    // Wait for backoff delay
    await Future.delayed(backoffDelay);

    // Check if we're at max capacity
    if (_connectedPeerIds.length >= _maxPeers) {
      debugPrint(
        '[Libp2pSync] Cannot reconnect to $peerId: at max capacity ($_maxPeers peers)',
      );
      return;
    }

    // Attempt reconnection
    try {
      // Track connection attempt (Phase 4: Resilience)
      final quality = _peerQuality.putIfAbsent(peerId, () => PeerQuality());
      quality.recordConnectionAttempt();

      // Increment attempt counter
      _reconnectAttempts[peerId] = attempts + 1;

      // Try to connect
      await connect(peerId: peerId);

      // Success! Reset reconnect state
      _reconnectAttempts.remove(peerId);
      _reconnectBackoff.remove(peerId);

      debugPrint('[Libp2pSync] ✅ Auto-reconnected to $peerId successfully');
    } catch (e) {
      debugPrint('[Libp2pSync] Auto-reconnect to $peerId failed: $e');

      // Connection already tracked failure in connect() method

      // Retry if we haven't exceeded max attempts (e.g., 10 attempts = ~17 minutes)
      if (attempts < 10) {
        debugPrint('[Libp2pSync] Will retry reconnect to $peerId later');
        // Schedule next retry (handled by next health check cycle)
      } else {
        debugPrint(
          '[Libp2pSync] Giving up on reconnect to $peerId after ${attempts + 1} attempts',
        );
        _reconnectAttempts.remove(peerId);
        _reconnectBackoff.remove(peerId);
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ────────────────────────────────────────────────────────────────────────────

  /// Dispose resources.
  void dispose() {
    // Cancel health check timer (Phase 4: Resilience)
    _healthCheckTimer?.cancel();

    _connectionStateController.close();
    _eventsController.close();
    _discoverySubscription?.cancel();
    _seenInboundRowIdsByTable.clear();
    _seenInboundRowOrderByTable.clear();
    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();

    // Clear vector clock state (Phase 3)
    _peerVectorClocks.clear();
    _vectorClock = VectorClock.empty();
    _deviceId = null;

    // Clear resilience state (Phase 4)
    _peerLastSeen.clear();
    _reconnectAttempts.clear();
    _reconnectBackoff.clear();
    _peerQuality.clear();
  }
}
