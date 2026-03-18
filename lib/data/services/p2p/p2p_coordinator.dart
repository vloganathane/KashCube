import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/peer_device.dart';
import '../../models/trusted_peer.dart';
import '../database_helper.dart';
import '../identity_service.dart';
import 'p2p_auth_service.dart';
import 'p2p_client.dart';
import 'p2p_discovery_service.dart';
import 'p2p_merge_service.dart';
import 'p2p_server.dart';

// ── Syncable tables — ordered by FK dependency tree ──────────────────────────

/// Tables that participate in P2P LAN sync, in the order they must be synced.
///
/// Parent tables appear before child tables to respect FK constraints.
/// Note: integer FK columns (e.g. `invoices.quote_id`) reference the remote
/// device's local PK — this is a known limitation of integer-PK-based FK sync.
/// FK violations are caught per-row and retried on the next sync cycle.
const _syncableTables = [
  // Root tables (no FK deps on other syncable tables)
  'businesses',
  'parties',
  'accounts',
  'categories',
  'item_catalog',
  'budgets',
  // Mid-level tables
  'transactions',
  'credits',
  'loans',
  'scheduled_payments',
  'purchase_bills',
  'credit_payments',
  // Quotes before invoices (invoices.quote_id → quotes.id)
  'quotes',
  'invoices',
];

// ── SyncStatus ────────────────────────────────────────────────────────────────

/// Phase of the sync coordinator lifecycle.
enum SyncPhase { idle, starting, syncing, done, error }

/// Snapshot of what the coordinator is currently doing — consumed by the UI.
class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.peerName,
    this.message,
    this.results,
  });

  final SyncPhase phase;

  /// Display name of the peer being synced (null when idle/starting/error).
  final String? peerName;

  /// Human-readable progress message.
  final String? message;

  /// Per-table merge results from the last completed sync cycle.
  final List<MergeResult>? results;

  @override
  String toString() => 'SyncStatus($phase, peer=$peerName)';
}

// ── P2pCoordinator ────────────────────────────────────────────────────────────

/// Orchestrates all P2P LAN sync components:
///
/// 1. Starts the shelf HTTP server ([P2pServer]) so peers can pull/push.
/// 2. Starts mDNS broadcast + discovery ([P2pDiscoveryService]).
/// 3. When a trusted peer is discovered, runs a full sync cycle:
///    - For each syncable table: pull remote rows → merge → push local changes.
///    - Updates [SyncWatermark] rows after each successful table sync.
///
/// Security: all HTTP traffic is HMAC-SHA256 signed via [P2pAuthService].
/// Privacy: 100% local LAN — no data ever leaves the device over the internet.
///
/// Usage:
/// ```dart
/// await P2pCoordinator.instance.start(db: db, identity: identity);
/// // …
/// await P2pCoordinator.instance.stop();
/// ```
class P2pCoordinator {
  P2pCoordinator._();
  static final P2pCoordinator instance = P2pCoordinator._();

  Database? _db;
  String?   _identityId;
  Uint8List? _deviceKeyBytes; // Ed25519 seed — used to decrypt stored peer secrets

  bool _running = false;

  // Peer identity IDs currently in an active sync cycle.
  final _activeSyncs = <String>{};

  // In-memory cache of trusted peer identity IDs — kept in sync with the
  // trusted_peers table so _isTrustedPeer() can answer synchronously.
  final _trustedPeerIds = <String>{};

  StreamSubscription<List<PeerDevice>>? _peerSub;

  final _statusController = StreamController<SyncStatus>.broadcast();

  /// Live stream of coordinator status for the Devices UI screen.
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// The most recently emitted [SyncStatus] — replayed to new subscribers
  /// so the UI shows the correct state when the screen is (re-)opened.
  SyncStatus _currentStatus = const SyncStatus(phase: SyncPhase.idle);
  SyncStatus get currentStatus => _currentStatus;

  bool get isRunning => _running;

  /// Loads the Ed25519 private key seed from [IdentityService] — used as a
  /// fallback in [pairWithPeer] when the coordinator has not been started yet.
  Future<Uint8List> _loadDeviceKeyBytes() async {
    final seedB64 = await IdentityService.instance.exportIdentityPrivateKeySeed();
    if (seedB64 == null) {
      throw StateError('[P2pCoordinator] Identity key not found — ensure identity is initialized before pairing.');
    }
    return Uint8List.fromList(base64.decode(seedB64));
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the coordinator.
  ///
  /// [db]          — open SQLite database (from [DatabaseHelper.instance])
  /// [identity]    — the local device's identity (from [IdentityService])
  /// [displayName] — human-readable name broadcast via mDNS
  /// [businessName]— optional active business name for mDNS TXT record
  Future<void> start({
    required Database db,
    required IdentityService identity,
    required String displayName,
    String? businessName,
  }) async {
    if (_running) return;
    _running = true;
    _db = db;
    _identityId = identity.identityId;

    _emit(const SyncStatus(phase: SyncPhase.starting, message: 'Starting P2P sync…'));

    // Decrypt peer secrets using the Ed25519 private key seed.
    final seedB64 = await identity.exportIdentityPrivateKeySeed();
    _deviceKeyBytes = seedB64 != null
        ? Uint8List.fromList(base64.decode(seedB64))
        : null;

    // Pre-load trusted peer IDs for synchronous isTrusted checks.
    await _refreshTrustedPeerCache(db);

    // Start the HTTP server — provides pull/push endpoints for remote peers.
    await P2pServer.instance.start(
      secretForPeer: _secretForPeer,
      onPull:        _handlePull,
      onPush:        _handlePush,
    );

    final port = P2pServer.instance.port!;

    // Broadcast presence and start scanning for peers.
    await P2pDiscoveryService.instance.startBroadcast(
      identityId:   _identityId!,
      displayName:  displayName,
      port:         port,
      businessName: businessName,
    );

    await P2pDiscoveryService.instance.startDiscovery(
      localIdentityId: _identityId!,
      onTrusted:       _isTrustedPeer,
    );

    // React when the peer list changes.
    _peerSub = P2pDiscoveryService.instance.peersStream.listen(
      _onPeersChanged,
      onError: (e) => debugPrint('[P2pCoordinator] Discovery error: $e'),
    );

    _emit(SyncStatus(
      phase:   SyncPhase.idle,
      message: 'Listening on port $port',
    ));
    debugPrint('[P2pCoordinator] Started on port $port');
  }

  /// Stops the coordinator and releases all resources.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _peerSub?.cancel();
    _peerSub = null;

    await P2pDiscoveryService.instance.stopDiscovery();
    await P2pDiscoveryService.instance.stopBroadcast();
    await P2pServer.instance.stop();

    _activeSyncs.clear();
    _trustedPeerIds.clear();
    _db = null;
    _deviceKeyBytes = null;

    _emit(const SyncStatus(phase: SyncPhase.idle, message: 'P2P sync stopped'));
    debugPrint('[P2pCoordinator] Stopped');
  }

  void dispose() {
    stop();
    _statusController.close();
  }

  // ── Peer event handling ───────────────────────────────────────────────────

  void _onPeersChanged(List<PeerDevice> peers) {
    for (final peer in peers) {
      if (!peer.isTrusted)      continue;
      if (!peer.isReachable)    continue;
      if (_activeSyncs.contains(peer.identityId)) continue;
      _syncWithPeer(peer); // fire and forget — errors caught internally
    }
  }

  // ── Sync cycle ────────────────────────────────────────────────────────────

  Future<void> _syncWithPeer(PeerDevice peer) async {
    _activeSyncs.add(peer.identityId);
    final db = _db;
    if (db == null) {
      _activeSyncs.remove(peer.identityId);
      return;
    }

    _emit(SyncStatus(
      phase:    SyncPhase.syncing,
      peerName: peer.displayName,
      message:  'Syncing with ${peer.displayName}…',
    ));

    try {
      final secret = await _secretForPeer(peer.identityId);
      if (secret == null) {
        _activeSyncs.remove(peer.identityId);
        return;
      }

      final client = P2pClient(
        baseUrl:      peer.baseUrl,
        identityId:   _identityId!,
        sharedSecret: secret,
      );

      // Confirm it's still a KashCube server.
      if (!await client.hello()) {
        debugPrint('[P2pCoordinator] hello() failed for ${peer.displayName}');
        client.dispose();
        _activeSyncs.remove(peer.identityId);
        return;
      }

      final allResults = <MergeResult>[];

      for (final table in _syncableTables) {
        try {
          final result = await _syncTable(
            db:         db,
            client:     client,
            peer:       peer,
            table:      table,
          );
          if (result != null) allResults.add(result);
        } catch (e) {
          // Per-table failure (e.g. FK violation) — log and continue.
          debugPrint('[P2pCoordinator] Table $table sync error: $e');
        }
      }

      client.dispose();

      // Stamp last_seen_at on the TrustedPeer row.
      await _stampLastSeen(db, peer.identityId);

      _emit(SyncStatus(
        phase:    SyncPhase.done,
        peerName: peer.displayName,
        message:  'Sync complete with ${peer.displayName}',
        results:  allResults,
      ));

      debugPrint('[P2pCoordinator] Sync done with ${peer.displayName} '
          '(${allResults.fold(0, (s, r) => s + r.inserted + r.updated)} changes)');
    } catch (e) {
      _emit(SyncStatus(
        phase:    SyncPhase.error,
        peerName: peer.displayName,
        message:  'Sync failed: $e',
      ));
      debugPrint('[P2pCoordinator] Sync error with ${peer.displayName}: $e');
    } finally {
      _activeSyncs.remove(peer.identityId);
    }
  }

  /// Syncs one [table] with a [peer]:
  ///  1. Pull remote rows → merge.
  ///  2. Push local rows newer than watermark.
  ///  3. Advance the watermark.
  ///
  /// Returns the merged [MergeResult], or null if nothing happened.
  Future<MergeResult?> _syncTable({
    required Database db,
    required P2pClient client,
    required PeerDevice peer,
    required String table,
  }) async {
    final watermarkTs = await getWatermarkForTest(db, peer.identityId, table);
    final afterMs     = watermarkTs?.millisecondsSinceEpoch ?? 0;

    // ── Pull remote rows ──────────────────────────────────────────────────
    final pullResponse = await client.pull(
      table:        table,
      afterVersion: afterMs,
    );

    MergeResult? mergeResult;
    if (pullResponse != null) {
      final remoteRows = (pullResponse['rows'] as List?)
          ?.cast<Map<String, dynamic>>() ?? [];

      if (remoteRows.isNotEmpty) {
        mergeResult = await P2pMergeService.instance.mergeTable(
          db:         db,
          table:      table,
          remoteRows: remoteRows,
          deviceId:   _identityId!,
        );
      }
    }

    // ── Push local rows ───────────────────────────────────────────────────
    final localRows = await queryLocalChangesForTest(db, table, afterMs);
    if (localRows.isNotEmpty) {
      await client.push(table: table, rows: localRows);
    }

    // ── Advance watermark ─────────────────────────────────────────────────
    final now = DateTime.now().toUtc();
    await upsertWatermarkForTest(db, peer.identityId, table, now);

    return mergeResult;
  }

  // ── DB helpers ────────────────────────────────────────────────────────────

  /// Returns rows from [table] with `updated_at` after [afterEpochMs].
  @visibleForTesting
  Future<List<Map<String, dynamic>>> queryLocalChangesForTest(
    Database db,
    String table,
    int afterEpochMs,
  ) async {
    try {
      if (afterEpochMs == 0) {
        // First sync — send everything that isn't deleted.
        return await db.rawQuery(
          'SELECT * FROM $table WHERE deleted_at IS NULL LIMIT 500',
        );
      }
      final cutoff = DateTime.fromMillisecondsSinceEpoch(afterEpochMs, isUtc: true)
          .toIso8601String();
      return await db.rawQuery(
        'SELECT * FROM $table WHERE updated_at > ? LIMIT 500',
        [cutoff],
      );
    } catch (e) {
      debugPrint('[P2pCoordinator] queryLocalChanges($table): $e');
      return [];
    }
  }

  /// Reads the stored watermark timestamp for [peerIdentityId]+[table].
  @visibleForTesting
  Future<DateTime?> getWatermarkForTest(
    Database db,
    String peerIdentityId,
    String table,
  ) async {
    final rows = await db.rawQuery(
      'SELECT last_synced_at FROM sync_watermarks '
      'WHERE peer_identity_id = ? AND table_name = ? LIMIT 1',
      [peerIdentityId, table],
    );
    if (rows.isEmpty) return null;
    final v = rows.first['last_synced_at'];
    if (v == null) return null;
    return DateTime.tryParse(v as String)?.toUtc();
  }

  /// Upserts a watermark row for [peerIdentityId]+[table].
  @visibleForTesting
  Future<void> upsertWatermarkForTest(
    Database db,
    String peerIdentityId,
    String table,
    DateTime lastSyncedAt,
  ) async {
    await db.rawInsert(
      '''
      INSERT INTO sync_watermarks (peer_identity_id, table_name, last_synced_at)
      VALUES (?, ?, ?)
      ON CONFLICT(peer_identity_id, table_name)
      DO UPDATE SET last_synced_at = excluded.last_synced_at
      ''',
      [peerIdentityId, table, lastSyncedAt.toIso8601String()],
    );
  }

  /// Stamps `last_seen_at` on the [TrustedPeer] row.
  Future<void> _stampLastSeen(Database db, String peerIdentityId) async {
    await db.rawUpdate(
      'UPDATE trusted_peers SET last_seen_at = ?, last_synced_at = ? '
      'WHERE peer_identity_id = ?',
      [
        DateTime.now().toUtc().toIso8601String(),
        DateTime.now().toUtc().toIso8601String(),
        peerIdentityId,
      ],
    );
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────

  /// Fetches and decrypts the shared secret for [peerIdentityId].
  /// Returns null if the peer is unknown or the key is unavailable.
  Future<Uint8List?> _secretForPeer(String peerIdentityId) async {
    final db = _db;
    if (db == null || _deviceKeyBytes == null) return null;
    try {
      final rows = await db.rawQuery(
        'SELECT shared_secret_enc FROM trusted_peers '
        'WHERE peer_identity_id = ? AND is_active = 1 LIMIT 1',
        [peerIdentityId],
      );
      if (rows.isEmpty) return null;
      final enc = rows.first['shared_secret_enc'] as String;
      return await P2pAuthService.instance.decryptSecret(
        encryptedBase64: enc,
        deviceKey:       _deviceKeyBytes!,
      );
    } catch (e) {
      debugPrint('[P2pCoordinator] Cannot decrypt secret for $peerIdentityId: $e');
      return null;
    }
  }

  /// Returns true if [identityId] has an active [TrustedPeer] row.
  bool _isTrustedPeer(String identityId) =>
      _trustedPeerIds.contains(identityId);

  /// Loads (or refreshes) the in-memory trusted peer ID cache from the DB.
  Future<void> _refreshTrustedPeerCache(Database db) async {
    try {
      final rows = await db.rawQuery(
        'SELECT peer_identity_id FROM trusted_peers WHERE is_active = 1',
      );
      _trustedPeerIds
        ..clear()
        ..addAll(rows.map((r) => r['peer_identity_id'] as String));
    } catch (e) {
      debugPrint('[P2pCoordinator] Failed to load trusted peers: $e');
    }
  }

  // ── Server callbacks ──────────────────────────────────────────────────────

  /// Called by the server when a remote peer requests our rows for [table]
  /// with version (epoch ms) > [afterVersion].
  Future<Map<String, dynamic>> _handlePull(
    String table,
    int afterVersion,
  ) async {
    final rows = await queryLocalChangesForTest(_db!, table, afterVersion);
    return {'table': table, 'rows': rows};
  }

  /// Called by the server when a remote peer pushes rows for [table].
  Future<void> _handlePush(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (_db == null) return;
    await P2pMergeService.instance.mergeTable(
      db:         _db!,
      table:      table,
      remoteRows: rows,
      deviceId:   _identityId!,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _emit(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  // ── Public utility ────────────────────────────────────────────────────────

  /// Returns a read-only list of all currently discovered peers.
  List<PeerDevice> get discoveredPeers =>
      P2pDiscoveryService.instance.currentPeers;

  /// Trigger an immediate sync with all currently visible trusted peers.
  /// No-op if not running.
  Future<void> syncNow() async {
    if (!_running) return;
    final peers = P2pDiscoveryService.instance.currentPeers
        .where((p) => p.isTrusted && p.isReachable)
        .toList();
    for (final p in peers) {
      if (!_activeSyncs.contains(p.identityId)) {
        _syncWithPeer(p);
      }
    }
  }

  /// Pairs with a new peer given their [identityId] and raw [sharedSecret].
  ///
  /// Encrypts the secret with this device's key and inserts a [TrustedPeer]
  /// row. Call this after QR-code pairing completes.
  Future<TrustedPeer> pairWithPeer({
    required String peerIdentityId,
    required String peerDisplayName,
    required Uint8List sharedSecret,
    String? businessId,
  }) async {
    final db = _db ?? await DatabaseHelper.instance.database;

    // Load key bytes lazily — coordinator may not have been start()ed yet
    // (e.g., user pairs with LAN Sync toggled off).
    final keyBytes = _deviceKeyBytes ?? await _loadDeviceKeyBytes();

    final enc = await P2pAuthService.instance.encryptSecret(
      rawSecret: sharedSecret,
      deviceKey: keyBytes,
    );
    final peer = TrustedPeer(
      peerIdentityId:  peerIdentityId,
      peerName:        peerDisplayName,
      businessId:      businessId,
      sharedSecretEnc: enc,
      pairedAt:        DateTime.now().toUtc(),
      isActive:        true,
    );
    await db.insert(
      'trusted_peers',
      peer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // Update in-memory cache so subsequent discoveries mark this peer trusted.
    _trustedPeerIds.add(peerIdentityId);
    debugPrint('[P2pCoordinator] Paired with $peerDisplayName ($peerIdentityId)');
    return peer;
  }
}
