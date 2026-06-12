/// Abstract interface for peer-to-peer sync operations.
///
/// Implementations:
/// - [WebRTCSyncRepositoryImpl] — WebRTC-based LAN sync (current)
/// - [Libp2pSyncRepositoryImpl] — libp2p-based mesh sync (future)
///
/// This interface abstracts the sync transport layer, allowing the app to
/// swap between WebRTC and libp2p without changing business logic.
abstract class SyncRepository {
  // ── Connection Lifecycle ────────────────────────────────────────────────

  /// Initialize the sync system (load identity, prepare resources).
  Future<void> initialize();

  /// Connect to a specific peer by [peerId].
  ///
  /// For WebRTC: [peerId] is the identity_id from QR code pairing.
  /// For libp2p: [peerId] is the libp2p PeerId (base58-encoded public key).
  Future<void> connect({required String peerId});

  /// Disconnect from the current peer and release resources.
  Future<void> disconnect();

  /// Stream of connection state changes.
  ///
  /// Emits [SyncConnectionState] enum values as the connection progresses
  /// through discovery, connection, syncing, and disconnection.
  Stream<SyncConnectionState> get connectionState;

  // ── Discovery ───────────────────────────────────────────────────────────

  /// Discover available sync peers on the local network.
  ///
  /// For WebRTC: mDNS-based discovery of paired devices.
  /// For libp2p: mDNS (local network) + DHT (internet).
  ///
  /// Returns a stream that emits updated peer lists as peers appear/disappear.
  Stream<List<SyncPeer>> discoverPeers();

  /// Stop peer discovery to conserve battery.
  Future<void> stopDiscovery();

  // ── Sync Operations ─────────────────────────────────────────────────────

  /// Sync a single table with the connected peer.
  ///
  /// Performs bidirectional sync:
  /// 1. Pull remote changes (rows newer than last watermark)
  /// 2. Push local changes (rows modified since last sync)
  /// 3. Update watermark for this peer+table
  Future<void> syncTable(String tableName);

  /// Sync all syncable tables in sequence.
  ///
  /// Equivalent to calling [syncTable] for every table in the sync registry.
  Future<void> syncAllTables();

  /// Get current sync progress (which tables completed, how many rows).
  Future<SyncProgress> getSyncProgress();

  // ── Real-time Push ──────────────────────────────────────────────────────

  /// Push a single row to the connected peer in real-time.
  ///
  /// Used for live updates: when the user creates/edits a transaction, push
  /// it immediately instead of waiting for the next [syncTable] call.
  Future<void> pushRow({
    required String table,
    required Map<String, dynamic> row,
  });

  /// Push multiple rows to the connected peer (batch push).
  Future<void> pushRows({
    required String table,
    required List<Map<String, dynamic>> rows,
  });

  // ── Events ──────────────────────────────────────────────────────────────

  /// Stream of sync lifecycle events (started, completed, errors).
  ///
  /// Subscribe to this to show toast notifications or update sync status UI.
  Stream<SyncEvent> get events;
}

// ═════════════════════════════════════════════════════════════════════════════
// Data Classes
// ═════════════════════════════════════════════════════════════════════════════

/// Represents a discovered sync peer.
class SyncPeer {
  const SyncPeer({
    required this.peerId,
    required this.displayName,
    this.deviceType,
    required this.discoveredAt,
  });

  /// Unique peer identifier.
  ///
  /// - WebRTC: `identity_id` from `my_identity` table
  /// - libp2p: `PeerId` (base58-encoded Ed25519 public key)
  final String peerId;

  /// Human-readable device name (e.g., "Logan's Phone", "Tablet").
  final String displayName;

  /// Device type hint (e.g., "android", "ios", "web", "desktop").
  final String? deviceType;

  /// When this peer was discovered (for sorting by recency).
  final DateTime discoveredAt;

  @override
  String toString() => 'SyncPeer($displayName, $peerId)';
}

/// Connection state of the sync session.
enum SyncConnectionState {
  /// No peer connected, idle.
  disconnected,

  /// Actively discovering peers via mDNS/DHT.
  discovering,

  /// Connection handshake in progress (WebRTC signaling, libp2p dial).
  connecting,

  /// Connected to peer, ready to sync.
  connected,

  /// Actively syncing tables (pull/push in progress).
  syncing,

  /// Connection or sync error occurred.
  error,
}

/// Sync progress snapshot.
class SyncProgress {
  const SyncProgress({
    required this.completedTables,
    required this.pendingTables,
    required this.rowsSynced,
    required this.rowsPending,
  });

  /// Set of table names that have completed syncing.
  final Set<String> completedTables;

  /// Set of table names that are pending or in progress.
  final Set<String> pendingTables;

  /// Total number of rows successfully synced (inserted + updated).
  final int rowsSynced;

  /// Estimated remaining rows to sync (may be inaccurate for delta sync).
  final int rowsPending;

  /// Whether all tables have completed syncing.
  bool get isComplete => pendingTables.isEmpty;

  /// Percentage of tables completed (0-100).
  double get percentComplete {
    final total = completedTables.length + pendingTables.length;
    if (total == 0) return 100.0;
    return (completedTables.length / total) * 100.0;
  }

  @override
  String toString() =>
      'SyncProgress(${completedTables.length}/${completedTables.length + pendingTables.length} tables, $rowsSynced rows)';
}

// ═════════════════════════════════════════════════════════════════════════════
// Events
// ═════════════════════════════════════════════════════════════════════════════

/// Base class for sync lifecycle events.
sealed class SyncEvent {
  const SyncEvent();
}

/// Sync session started (after successful connection).
class SyncStarted extends SyncEvent {
  const SyncStarted();
}

/// A single table completed syncing.
class SyncTableCompleted extends SyncEvent {
  const SyncTableCompleted({
    required this.tableName,
    required this.rowsProcessed,
  });

  final String tableName;
  final int rowsProcessed; // Rows inserted + updated (not counting skipped)
}

/// All tables completed syncing successfully.
class SyncCompleted extends SyncEvent {
  const SyncCompleted({required this.totalRowsSynced, required this.duration});

  final int totalRowsSynced;
  final Duration duration;
}

/// Sync error occurred (connection lost, merge failure, etc.).
class SyncError extends SyncEvent {
  const SyncError({required this.message, this.error, this.stackTrace});

  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() => 'SyncError: $message${error != null ? ' ($error)' : ''}';
}

/// Peer disconnected mid-sync.
class SyncDisconnected extends SyncEvent {
  const SyncDisconnected({required this.reason});

  final String reason;
}
