import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_tables.dart';
import '../../models/peer_device.dart';
import '../../models/trusted_peer.dart';
import '../../../core/constants/app_constants.dart';
import '../database_helper.dart';
import '../identity_service.dart';
import '../sync/generic_sync_query_builder.dart';
import '../sync/transport/sync_signaling_messages.dart';
import '../sync/sync_table_registry.dart';
import '../sync/sync_table_state_store.dart';
import '../sync_event_bus.dart';
import '../web/web_companion_service.dart';
import '../web/web_session_service.dart';
import 'p2p_auth_service.dart';
import 'p2p_client.dart';
import 'p2p_discovery_service.dart';
import 'p2p_merge_service.dart';
import 'p2p_server.dart';

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
  String?   _displayName;
  Uint8List? _deviceKeyBytes; // Ed25519 seed — used to decrypt stored peer secrets

  bool _running = false;
  /// True while a start() call is in progress — prevents concurrent starts
  /// (e.g. _restore() + UI toggle racing before the server is bound).
  bool _startInProgress = false;

  /// True when the HTTP server was started exclusively for the web companion
  /// (without mDNS broadcast/discovery).  The server stays alive even when
  /// the LAN sync toggle is off so the browser companion keeps working.
  bool _serverOnlyMode = false;
  Timer? _webPushTimer;
  StreamSubscription<String>? _syncEventSub;
  bool _webPushInFlight = false;

  // Per-table high-watermark for incremental phone -> browser PUSH.
  // Backed by SyncTableStateStore; this map is a warm in-memory cache.
  final Map<String, DateTime> _webLastPushedAt = {};
  final Map<String, int> _webLastPushedVersion = {};
  final Map<String, SyncTablePlan> _webSyncPlans = {};

  // Cache table columns for schema-aware web delta queries.
  final Map<String, Set<String>> _tableColumnsCache = {};

  // Peer identity IDs currently in an active sync cycle.
  final _activeSyncs = <String>{};

  // Staged signaling frames keyed by browser session id.
  // This keeps the protocol deterministic while WebRTC peer wiring lands.
  final Map<String, Map<String, dynamic>> _webRtcSignalState = {};

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

  /// Port the embedded HTTP server is listening on (null when not running).
  int? get serverPort => P2pServer.instance.port;

  /// Local identity id currently active in the coordinator.
  String? get localIdentityId => _identityId;

  /// Readiness probe used by the "Open on Laptop" screen before showing QR.
  Future<bool> isServerHealthy() => P2pServer.instance.isHealthy();

  bool approveBrowserSession({
    required String sessionId,
    required String challenge,
  }) {
    return P2pServer.instance.approveBrowserSession(
      sessionId: sessionId,
      challenge: challenge,
    );
  }

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
    // Already fully running — nothing to do.
    if (_running && P2pServer.instance.port != null) return;
    // Another start() is in progress — bail; the in-flight call will finish.
    if (_startInProgress) return;
    _startInProgress = true;
    _running = true;
    _db = db;
    _identityId  = identity.identityId;
    _displayName = displayName;

    _emit(const SyncStatus(phase: SyncPhase.starting, message: 'Starting P2P sync…'));

    // Decrypt peer secrets using the Ed25519 private key seed.
    final seedB64 = await identity.exportIdentityPrivateKeySeed();
    _deviceKeyBytes = seedB64 != null
        ? Uint8List.fromList(base64.decode(seedB64))
        : null;

    // Pre-load trusted peer IDs for synchronous isTrusted checks.
    await _refreshTrustedPeerCache(db);
    await _logDiscoveredSyncPlans(db);

    // Start the HTTP server — provides pull/push endpoints for remote peers.
    await P2pServer.instance.start(
      localIdentityId: _identityId!,
      localDisplayName: displayName,
      secretForPeer:  _secretForPeer,
      onPull:         _handlePull,
      onPush:         _handlePush,
      onPairRequest:  _handlePairRequest,
    );

    final port = P2pServer.instance.port!;

    // Broadcast presence and start scanning for peers.
    // mDNS is best-effort: on some platforms (macOS sandbox, restricted
    // networks) Bonjour multicast may be unavailable.  A failure here
    // must not prevent the HTTP server from being used — e.g. for the
    // Web Companion or manual-IP pairing.
    try {
      await P2pDiscoveryService.instance.startBroadcast(
        identityId:   _identityId!,
        displayName:  displayName,
        port:         port,
        businessName: businessName,
      );
    } catch (e) {
      debugPrint('[P2pCoordinator] mDNS broadcast unavailable (non-fatal): $e');
    }

    try {
      await P2pDiscoveryService.instance.startDiscovery(
        localIdentityId: _identityId!,
        onTrusted:       _isTrustedPeer,
      );
    } catch (e) {
      debugPrint('[P2pCoordinator] mDNS discovery unavailable (non-fatal): $e');
    }

    // React when the peer list changes.
    _peerSub = P2pDiscoveryService.instance.peersStream.listen(
      _onPeersChanged,
      onError: (e) => debugPrint('[P2pCoordinator] Discovery error: $e'),
    );

    _startWebPushLoop();

    _emit(SyncStatus(
      phase:   SyncPhase.idle,
      message: 'Listening on port $port',
    ));

    // Enable web companion on the shared server.
    P2pServer.instance.enableWebCompanion(
      deviceName:    displayName,
      schemaVersion: AppConstants.dbVersion,
      onWrite:       _handleWebWrite,
      onSignalFrame: _handleWebSignalFrame,
      onMediaUpload: _handleWebMediaUpload,
    );
    // Arm the wake-lock service so the server keeps the CPU awake while a
    // browser tab is open.  Idempotent — no-op if already attached.
    WebCompanionService.instance.attach();

    debugPrint('[P2pCoordinator] Started on port $port');
    _startInProgress = false;
  }

  Future<void> _logDiscoveredSyncPlans(Database db) async {
    try {
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
      _webSyncPlans
        ..clear()
        ..addEntries(plans.map((p) => MapEntry(p.tableName, p)));

      // Warm the in-memory watermark cache from persisted state.
      if (_identityId != null) {
        for (final plan in plans) {
          final state = await SyncTableStateStore.instance.read(
            peerIdentityId: _identityId!,
            tableName: plan.tableName,
          );
          if (state != null) {
            if (state.lastSyncedAt != null) {
              _webLastPushedAt[plan.tableName] = state.lastSyncedAt!;
            }
            if (state.lastVersion != null) {
              _webLastPushedVersion[plan.tableName] = state.lastVersion!;
            }
          }
        }
      }

      final deltaTs = plans.where((p) => p.mode == SyncMode.deltaTs).length;
      final deltaVersion =
          plans.where((p) => p.mode == SyncMode.deltaVersion).length;
      final snapshot = plans.where((p) => p.mode == SyncMode.snapshot).length;

      debugPrint(
        '[SyncRegistry][Phone] discovered=${plans.length} delta_ts=$deltaTs delta_version=$deltaVersion snapshot=$snapshot',
      );
    } catch (e) {
      debugPrint('[SyncRegistry][Phone] discovery failed: $e');
    }
  }

  /// Stops the coordinator and releases all resources.
  // ── Server-only mode (web companion without LAN sync) ────────────────────

  /// Starts only the HTTP server and web companion — no mDNS broadcast or
  /// device discovery.  Use this when the user opens "Open on Laptop" without
  /// having LAN sync enabled, so the browser companion works independently.
  ///
  /// Idempotent: if the full coordinator (or another server-only session) is
  /// already running this is a no-op.
  Future<void> startServerOnly({
    required Database db,
    required IdentityService identity,
    required String displayName,
  }) async {
    // Full coordinator already running — just ensure web companion is enabled.
    if (_running && P2pServer.instance.port != null) {
      P2pServer.instance.enableWebCompanion(
        deviceName:    displayName,
        schemaVersion: AppConstants.dbVersion,
        onWrite:       _handleWebWrite,
        onSignalFrame: _handleWebSignalFrame,
        onMediaUpload: _handleWebMediaUpload,
      );
      return;
    }
    // Server-only already up.
    if (_serverOnlyMode && P2pServer.instance.port != null) return;

    _db          = db;
    _identityId  = identity.identityId;
    _displayName = displayName;

    final seedB64 = await identity.exportIdentityPrivateKeySeed();
    _deviceKeyBytes = seedB64 != null
        ? Uint8List.fromList(base64.decode(seedB64))
        : null;

    await _logDiscoveredSyncPlans(db);
    _startWebPushLoop();

    await P2pServer.instance.start(
      localIdentityId: _identityId!,
      localDisplayName: displayName,
      secretForPeer:  _secretForPeer,
      onPull:         _handlePull,
      onPush:         _handlePush,
      onPairRequest:  _handlePairRequest,
    );

    P2pServer.instance.enableWebCompanion(
      deviceName:    displayName,
      schemaVersion: AppConstants.dbVersion,
      onWrite:       _handleWebWrite,
      onSignalFrame: _handleWebSignalFrame,
      onMediaUpload: _handleWebMediaUpload,
    );
    // Arm the wake-lock service (idempotent).
    WebCompanionService.instance.attach();

    _serverOnlyMode = true;
    debugPrint('[P2pCoordinator] Server-only mode started on port ${P2pServer.instance.port}');
  }

  /// Stops the HTTP server when it was started via [startServerOnly] and the
  /// full coordinator is not running.  No-op if the full coordinator is active.
  Future<void> stopServerOnly() async {
    if (_running) return; // full coordinator owns the server
    if (!_serverOnlyMode) return;
    _serverOnlyMode = false;

    _webPushTimer?.cancel();
    _webPushTimer = null;
    _webLastPushedAt.clear();
    _webLastPushedVersion.clear();
    _webSyncPlans.clear();
    _tableColumnsCache.clear();
    await _syncEventSub?.cancel();
    _syncEventSub = null;

    await P2pServer.instance.stop();
    _db = null;
    _deviceKeyBytes = null;
    debugPrint('[P2pCoordinator] Server-only mode stopped');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _startInProgress = false;

    await _peerSub?.cancel();
    _peerSub = null;

    _webPushTimer?.cancel();
    _webPushTimer = null;
    _webLastPushedAt.clear();
    _webLastPushedVersion.clear();
    _webSyncPlans.clear();
    _tableColumnsCache.clear();
    await _syncEventSub?.cancel();
    _syncEventSub = null;

    await P2pDiscoveryService.instance.stopDiscovery();
    await P2pDiscoveryService.instance.stopBroadcast();

    // Only stop the HTTP server if the web companion is not serving a browser
    // session and we are not in server-only mode.  This keeps the server alive
    // when the user disables LAN sync while a browser tab is open.
    if (!_serverOnlyMode && !P2pServer.instance.hasBrowserConnected) {
      await P2pServer.instance.stop();
    } else {
      debugPrint('[P2pCoordinator] Server kept alive for web companion');
    }

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
      // Use the live in-memory set, not the stale flag set at discovery time.
      // This ensures newly-paired peers sync immediately without waiting for
      // the next mDNS event to re-resolve and re-set isTrusted.
      if (!_isTrustedPeer(peer.identityId)) continue;
      if (!peer.isReachable)                continue;
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

      // Send a back-pair notification so the peer stores us as a trusted
      // device if it hasn't already (makes pairing bidirectional).
      await client.pair(
        myIdentityId:      _identityId!,
        myPublicKeyBase64: IdentityService.instance.identityPublicKeyBase64,
        myDisplayName:     _displayName ?? 'KashCube',
      );

      // Confirm it's still a KashCube server.
      if (!await client.hello()) {
        debugPrint('[P2pCoordinator] hello() failed for ${peer.displayName}');
        client.dispose();
        _activeSyncs.remove(peer.identityId);
        return;
      }

      final allResults = <MergeResult>[];

      var syncTables = _peerSyncTables();
      if (syncTables.isEmpty) {
        await _logDiscoveredSyncPlans(db);
        syncTables = _peerSyncTables();
      }

      for (final table in syncTables) {
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
        final plan = _webSyncPlans[table];
        mergeResult = await P2pMergeService.instance.mergeTable(
          db:         db,
          table:      table,
          remoteRows: remoteRows,
          deviceId:   _identityId!,
          keyColumn:  plan?.keyColumn ?? 'sync_id',
          mode:       plan?.mode ?? SyncMode.deltaTs,
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
      final columns = await _getTableColumns(db, table);
      final hasUpdatedAt = columns.contains('updated_at');
      final hasCreatedAt = columns.contains('created_at');
      final hasDeletedAt = columns.contains('deleted_at');

      String sqlUtcExpr(String expr) {
        return "CASE WHEN $expr LIKE '%Z' THEN julianday($expr) ELSE julianday($expr, 'utc') END";
      }

      if (afterEpochMs == 0) {
        final where = hasDeletedAt ? ' WHERE deleted_at IS NULL' : '';
        return await db.rawQuery('SELECT * FROM $table$where LIMIT 500');
      }

      if (!hasUpdatedAt && !hasCreatedAt) {
        return [];
      }

      final cutoff = DateTime.fromMillisecondsSinceEpoch(afterEpochMs, isUtc: true)
          .toIso8601String();
      final where = <String>[];
      final args = <Object?>[];

      if (hasUpdatedAt && hasCreatedAt) {
        where.add("${sqlUtcExpr('COALESCE(updated_at, created_at)')} > julianday(?)");
        args.add(cutoff);
      } else if (hasUpdatedAt) {
        where.add("${sqlUtcExpr('updated_at')} > julianday(?)");
        args.add(cutoff);
      } else if (hasCreatedAt) {
        where.add("${sqlUtcExpr('created_at')} > julianday(?)");
        args.add(cutoff);
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

      return await db.rawQuery(
        'SELECT * FROM $table$whereSql$orderBy LIMIT 500',
        args,
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
    final plan = _webSyncPlans[table];
    await P2pMergeService.instance.mergeTable(
      db:         _db!,
      table:      table,
      remoteRows: rows,
      deviceId:   _identityId!,
      keyColumn:  plan?.keyColumn ?? 'sync_id',
      mode:       plan?.mode ?? SyncMode.deltaTs,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _emit(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
  /// Handles a back-pair request from [identityId].
  ///
  /// Derives the shared secret from our own pubkey + their pubkey, verifies
  /// the HMAC proof, then stores them as a trusted peer.
  /// Idempotent: returns true immediately if we already trust this peer.
  Future<bool> _handlePairRequest(
    String identityId,
    String peerPublicKeyBase64,
    String displayName,
    String proof,
  ) async {
    // Already trusted — idempotent.
    if (_isTrustedPeer(identityId)) return true;

    try {
      final myPubKeyBytes     = base64.decode(IdentityService.instance.identityPublicKeyBase64);
      final peerPubKeyBytes   = base64.decode(peerPublicKeyBase64);
      final sharedSecret      = await P2pAuthService.instance.deriveSharedSecret(
        localPubKey:  Uint8List.fromList(myPubKeyBytes),
        remotePubKey: Uint8List.fromList(peerPubKeyBytes),
      );

      final expectedProof = P2pAuthService.instance.signPairProof(
        sharedSecret:     sharedSecret,
        senderIdentityId: identityId,
      );
      if (expectedProof != proof) {
        debugPrint('[P2pCoordinator] Back-pair rejected — invalid proof from $identityId');
        return false;
      }

      await pairWithPeer(
        peerIdentityId:  identityId,
        peerDisplayName: displayName,
        sharedSecret:    sharedSecret,
      );
      debugPrint('[P2pCoordinator] Back-paired with $displayName ($identityId)');
      return true;
    } catch (e) {
      debugPrint('[P2pCoordinator] Back-pair error from $identityId: $e');
      return false;
    }
  }
  // ── Public utility ────────────────────────────────────────────────────────

  /// Enables web companion on the shared server (idempotent — can be called
  /// after [start] if the display name changes).
  void enableWebCompanion({required String deviceName, required int schemaVersion}) {
    P2pServer.instance.enableWebCompanion(
      deviceName:    deviceName,
      schemaVersion: schemaVersion,
      onWrite:       _handleWebWrite,
      onSignalFrame: _handleWebSignalFrame,
      onMediaUpload: _handleWebMediaUpload,
    );
  }

  /// Disconnects the active browser WebSocket session.
  void disconnectBrowser() => P2pServer.instance.disconnectBrowser();

  bool get hasBrowserConnected => P2pServer.instance.hasBrowserConnected;

  /// Emits `true` each time a browser successfully authenticates.
  /// Delegate straight to the server's broadcast stream.
  Stream<bool> get browserConnectionStream =>
      P2pServer.instance.browserConnectionStream;

  void _startWebPushLoop() {
    _webPushTimer?.cancel();
    _webPushTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _pushLocalDeltasToWeb();
    });
    // Trigger immediately whenever a local table changes.
    _syncEventSub?.cancel();
    _syncEventSub = SyncEventBus.instance.stream.listen((_) {
      _pushLocalDeltasToWeb();
    });
  }

  Future<void> _pushLocalDeltasToWeb() async {
    if (!_running) {
      return;
    }
    if (_webPushInFlight) {
      return;
    }
    _webPushInFlight = true;

    try {
      final session = WebSessionService.instance.activeSession;
      if (session == null) {
        return;
      }

      final db = _db;
      if (db == null) {
        return;
      }

      for (final table in _webMirrorTables()) {
        try {
          final plan = _webSyncPlans[table]!;

          final query = GenericSyncQueryBuilder.buildOutboundQuery(
            plan:         plan,
            since:        _webLastPushedAt[table],
            afterVersion: _webLastPushedVersion[table],
          );
          final rows = await db.rawQuery(query.sql, query.args);

          if (rows.isEmpty) continue;

          session.pushRows(table, rows);

          // Advance the in-memory cursor and persist to sync_table_state.
          if (plan.mode == SyncMode.deltaTs) {
            final newTs = GenericSyncQueryBuilder.maxTimestamp(rows);
            _webLastPushedAt[table] = newTs;
            if (_identityId != null) {
              await SyncTableStateStore.instance.updateProgress(
                peerIdentityId: _identityId!,
                tableName:      table,
                syncMode:       plan.mode,
                schemaFingerprint: plan.schemaFingerprint,
                lastSyncedAt:   newTs,
              );
            }
          } else if (plan.mode == SyncMode.deltaVersion) {
            final newVer = GenericSyncQueryBuilder.maxVersion(rows);
            if (newVer != null) {
              _webLastPushedVersion[table] = newVer;
              if (_identityId != null) {
                await SyncTableStateStore.instance.updateProgress(
                  peerIdentityId: _identityId!,
                  tableName:      table,
                  syncMode:       plan.mode,
                  schemaFingerprint: plan.schemaFingerprint,
                  lastVersion:    newVer,
                );
              }
            }
          }
          // snapshot: no cursor to advance — always full scan.
        } catch (e) {
          debugPrint('[P2pCoordinator] Web delta push failed for $table: $e');
        }
      }
    } finally {
      _webPushInFlight = false;
    }
  }

  List<String> _peerSyncTables() {
    final tables = _webSyncPlans.values
        .where((plan) => plan.isP2pEligible && plan.mode == SyncMode.deltaTs)
        .map((plan) => plan.tableName)
        .toList()
      ..sort();
    return tables;
  }

  List<String> _webMirrorTables() {
    final tables = _webSyncPlans.values
        .where((plan) => plan.isWebEligible)
        .map((plan) => plan.tableName)
        .toList()
      ..sort();
    return tables;
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

  // Handles WRITE messages from the browser — merges directly into local DB.
  Future<void> _handleWebWrite(String table, Map<String, dynamic> row) async {
    final db = _db;
    if (db == null) {
      return;
    }

    final normalized = await _normalizeIncomingWebRow(db, table, row);
    // Always use the registry plan's key column so text-PK tables (e.g. settings)
    // are merged correctly. Falls back to 'sync_id' for tables not yet discovered.
    final plan = _webSyncPlans[table];
    await P2pMergeService.instance.mergeTable(
      db:         db,
      table:      table,
      remoteRows: [normalized],
      deviceId:   _identityId!,
      keyColumn:  plan?.keyColumn ?? 'sync_id',
      mode:       plan?.mode ?? SyncMode.deltaTs,
    );
    DatabaseHelper.instance.notifyChange(table);
    // Push the merged row back to the browser session if active.
    WebSessionService.instance.activeSession?.pushRows(table, [normalized]);
  }

  Future<List<Map<String, dynamic>>> _handleWebSignalFrame(
    Map<String, dynamic> frame,
  ) async {
    final type = (frame['type'] as String? ?? '').toUpperCase();
    debugPrint('[P2pCoordinator] Web signaling frame received: $type');

    if (!SyncSignalingMessages.isWebRtcSignalType(type)) {
      return [
        {
          'type': SyncSignalingMessages.signalError,
          'code': 'UNSUPPORTED_SIGNAL_TYPE',
          'reason': 'Unsupported signaling frame type',
          'source_type': type,
        },
      ];
    }

    final sessionId = frame['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      return [
        {
          'type': SyncSignalingMessages.signalError,
          'code': 'MISSING_SESSION_ID',
          'reason': 'session_id is required for signaling frames',
          'source_type': type,
        },
      ];
    }

    if (SyncSignalingMessages.requiresSdp(type)) {
      final sdp = frame['sdp']?.toString();
      if (sdp == null || sdp.isEmpty) {
        return [
          {
            'type': SyncSignalingMessages.signalError,
            'code': 'MISSING_SDP',
            'reason': 'sdp is required for offer/answer frames',
            'source_type': type,
            'session_id': sessionId,
          },
        ];
      }
    }

    if (SyncSignalingMessages.requiresCandidate(type) && frame['candidate'] == null) {
      return [
        {
          'type': SyncSignalingMessages.signalError,
          'code': 'MISSING_ICE_CANDIDATE',
          'reason': 'candidate is required for ice candidate frames',
          'source_type': type,
          'session_id': sessionId,
        },
      ];
    }

    final sessionState = _webRtcSignalState.putIfAbsent(
      sessionId,
      () => <String, dynamic>{},
    );
    sessionState['updated_at'] = DateTime.now().toUtc().toIso8601String();
    sessionState['session_id'] = sessionId;
    sessionState[type.toLowerCase()] = Map<String, dynamic>.from(frame);

    final signalId = frame['signal_id']?.toString();
    return [
      {
        'type': SyncSignalingMessages.signalAck,
        'status': 'staged',
        'source_type': type,
        'session_id': sessionId,
        if (signalId != null && signalId.isNotEmpty) 'signal_id': signalId,
      },
      {
        'type': SyncSignalingMessages.signalUnsupported,
        'reason': 'WebRTC peer connection engine is not enabled yet',
        'code': 'WEBRTC_ENGINE_NOT_READY',
        'source_type': type,
        'session_id': sessionId,
      },
    ];
  }

  Future<Map<String, dynamic>> _normalizeIncomingWebRow(
    Database db,
    String table,
    Map<String, dynamic> row,
  ) async {
    final normalized = Map<String, dynamic>.from(row);
    final columns = await _getTableColumns(db, table);
    final now = DateTime.now().toUtc().toIso8601String();

    if (columns.contains('sync_id')) {
      normalized['sync_id'] ??= _newSyncId();
    }
    if (columns.contains('updated_at')) {
      normalized['updated_at'] ??= now;
    }
    if (columns.contains('created_at')) {
      normalized['created_at'] ??= now;
    }
    if (columns.contains('version')) {
      normalized['version'] ??= 0;
    }

    if (table == AppTables.businesses && columns.contains('logo_path')) {
      final mediaId = normalized['logo_media_id']?.toString();
      final logoPath = normalized['logo_path']?.toString();
      if (mediaId != null && mediaId.isNotEmpty && (logoPath == null || logoPath.isEmpty)) {
        final resolved = await _resolveMediaPath(db, mediaId);
        if (resolved != null) {
          normalized['logo_path'] = resolved;
        }
      }
    }

    if (table == AppTables.parties && columns.contains('business_card_image_path')) {
      final mediaId = normalized['business_card_media_id']?.toString();
      final imagePath = normalized['business_card_image_path']?.toString();
      if (mediaId != null && mediaId.isNotEmpty && (imagePath == null || imagePath.isEmpty)) {
        final resolved = await _resolveMediaPath(db, mediaId);
        if (resolved != null) {
          normalized['business_card_image_path'] = resolved;
        }
      }
    }

    return normalized;
  }

  Future<String?> _resolveMediaPath(Database db, String mediaId) async {
    final rows = await db.query(
      AppTables.mediaAssets,
      columns: ['local_path'],
      where: 'media_id = ? AND deleted_at IS NULL',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['local_path'] as String?;
  }

  Future<Map<String, dynamic>> _handleWebMediaUpload({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final db = _db ?? await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc();
    final sha = sha256.convert(bytes).toString();

    final existing = await db.query(
      AppTables.mediaAssets,
      columns: ['media_id', 'local_path', 'sha256', 'byte_size', 'mime_type'],
      where: 'sha256 = ? AND byte_size = ? AND deleted_at IS NULL',
      whereArgs: [sha, bytes.length],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      final existingPath = row['local_path'] as String?;
      if (existingPath != null && File(existingPath).existsSync()) {
        return {
          'media_id': row['media_id'],
          'local_path': existingPath,
          'sha256': row['sha256'],
          'byte_size': row['byte_size'],
          'mime_type': row['mime_type'],
          'deduped': true,
        };
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media_assets'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final ext = _guessMediaExtension(fileName: fileName, mimeType: mimeType);
    final mediaId = _newSyncId();
    final localPath = p.join(mediaDir.path, '$mediaId$ext');
    await File(localPath).writeAsBytes(bytes, flush: true);

    await db.insert(
      AppTables.mediaAssets,
      {
        'media_id': mediaId,
        'sha256': sha,
        'mime_type': mimeType,
        'byte_size': bytes.length,
        'origin': 'web',
        'local_path': localPath,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    DatabaseHelper.instance.notifyChange(AppTables.mediaAssets);

    return {
      'media_id': mediaId,
      'local_path': localPath,
      'sha256': sha,
      'byte_size': bytes.length,
      'mime_type': mimeType,
      'deduped': false,
    };
  }

  String _guessMediaExtension({required String fileName, required String mimeType}) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) return '.jpg';
    if (lowerName.endsWith('.png')) return '.png';
    if (lowerName.endsWith('.webp')) return '.webp';
    if (mimeType.contains('png')) return '.png';
    if (mimeType.contains('webp')) return '.webp';
    return '.jpg';
  }

  String _newSyncId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    return '${now.toRadixString(16)}$rand';
  }

  /// Trigger an immediate sync with all currently visible trusted peers.
  /// No-op if not running.
  Future<void> syncNow() async {
    if (!_running) return;
    final peers = P2pDiscoveryService.instance.currentPeers
        .where((p) => _isTrustedPeer(p.identityId) && p.isReachable)
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

    // If the coordinator is already running and this peer is visible on the
    // LAN right now, kick off an immediate sync cycle.  This sends the
    // back-pair notification without waiting for the next mDNS event.
    if (_running) {
      for (final p in P2pDiscoveryService.instance.currentPeers) {
        if (p.identityId == peerIdentityId &&
            p.isReachable &&
            !_activeSyncs.contains(peerIdentityId)) {
          _syncWithPeer(p);
          break;
        }
      }
    }

    return peer;
  }

  /// Revokes trust for [peerIdentityId]:
  ///   - Sets `is_active = 0` in `trusted_peers`
  ///   - Removes from the in-memory cache (stops future syncs immediately)
  ///   - Deletes all `sync_watermarks` so a fresh full-sync runs if re-paired
  Future<void> revokePeer(String peerIdentityId) async {
    final db = _db ?? await DatabaseHelper.instance.database;
    await db.rawUpdate(
      'UPDATE trusted_peers SET is_active = 0 WHERE peer_identity_id = ?',
      [peerIdentityId],
    );
    await db.rawDelete(
      'DELETE FROM sync_watermarks WHERE peer_identity_id = ?',
      [peerIdentityId],
    );
    _trustedPeerIds.remove(peerIdentityId);
    debugPrint('[P2pCoordinator] Revoked trust for $peerIdentityId');
  }
}
