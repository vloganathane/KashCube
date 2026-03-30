import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/peer_device.dart';
import '../../data/models/trusted_peer.dart';
import '../../data/services/action_center_background_service.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/p2p/p2p_coordinator.dart';
import '../../data/services/p2p/p2p_discovery_service.dart';
import '../../data/services/p2p/p2p_server.dart';
import '../../data/services/web/web_companion_service.dart';
import '../providers/identity_provider.dart';
import '../providers/settings_provider.dart';

// ── Read-only stream providers ─────────────────────────────────────────────

/// Live list of peers currently visible on the LAN via mDNS.
///
/// Immediately yields [P2pDiscoveryService.currentPeers] so the UI shows the
/// already-discovered peers when the screen is (re-)opened mid-session,
/// matching the pattern used by [p2pSyncStatusProvider].
final p2pPeersProvider = StreamProvider<List<PeerDevice>>((ref) async* {
  yield P2pDiscoveryService.instance.currentPeers;
  yield* P2pDiscoveryService.instance.peersStream;
});

/// Current coordinator status (phase, peer name, progress message).
/// Immediately yields [P2pCoordinator.currentStatus] so the UI never
/// stays in the loading state when the screen is (re-)opened after a sync.
final p2pSyncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  yield P2pCoordinator.instance.currentStatus;
  yield* P2pCoordinator.instance.statusStream;
});

/// All active trusted (paired) peers, ordered newest-first.
/// Invalidate with [ref.invalidate(trustedPeersProvider)] after pairing.
final trustedPeersProvider = FutureProvider<List<TrustedPeer>>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'trusted_peers',
    where: 'is_active = 1',
    orderBy: 'paired_at DESC',
  );
  return rows.map(TrustedPeer.fromMap).toList();
});

// ── Enabled toggle (starts / stops the coordinator) ────────────────────────

/// SharedPreferences key that persists the user's LAN sync on/off choice
/// across app restarts.
const _kLanSyncEnabled = 'p2p_sync_enabled';

/// Manages whether LAN sync is active.
///
/// The enabled state is persisted in [SharedPreferences] under
/// [_kLanSyncEnabled] so the coordinator auto-restarts after an app relaunch
/// if the user had previously enabled it.
///
/// Calling [P2pEnabledNotifier.enable] starts [P2pCoordinator] and registers
/// the WorkManager probe task.  [disable] reverses both.
class P2pEnabledNotifier extends StateNotifier<bool> {
  P2pEnabledNotifier(this._ref) : super(false) {
    _restore();
  }

  final Ref _ref;

  /// Guard against concurrent enable() calls — e.g. _restore() and a UI
  /// toggle arriving before the first start() completes.
  bool _enabling = false;

  /// Reads the persisted preference and re-enables LAN sync if the user had
  /// it turned on before the app was last closed.
  Future<void> _restore() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final wasOn   = prefs.getBool(_kLanSyncEnabled) ?? false;
      if (wasOn && mounted) await enable();
    } catch (e) {
      debugPrint('[P2P] restore() failed: $e');
    }
  }

  Future<void> enable() async {
    if (state || _enabling) return;
    _enabling = true;
    try {
      final db = await DatabaseHelper.instance.database;
      // Wait for both the signing keypair AND the identity keypair to be
      // loaded — identityInitProvider runs ensureIdentityInitialized which
      // populates identityId used by P2pCoordinator.start().
      await _ref.read(identityInitProvider.future);
      final identity = await _ref.read(identityServiceProvider.future);
      final settings = _ref.read(settingsRepositoryProvider);
      final name     = await settings.get(SettingsKeys.ownerName);
      await P2pCoordinator.instance.start(
        db:          db,
        identity:    identity,
        displayName: (name == null || name.trim().isEmpty) ? 'KashCube' : name.trim(),
      );
      await registerP2pSyncTask();
      if (mounted) {
        state = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kLanSyncEnabled, true);
      }
    } catch (e, s) {
      debugPrint('[P2P] enable() failed: $e\n$s');
      // If the HTTP server is actually bound, mark as enabled despite the
      // error (e.g. mDNS registration failure after server started).
      if (mounted && P2pCoordinator.instance.serverPort != null) {
        state = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kLanSyncEnabled, true);
      }
    } finally {
      _enabling = false;
    }
  }

  Future<void> disable() async {
    if (!state) return;
    await P2pCoordinator.instance.stop();
    await cancelP2pSyncTask();
    if (mounted) {
      state = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLanSyncEnabled, false);
    }
  }
}

final p2pEnabledProvider =
    StateNotifierProvider<P2pEnabledNotifier, bool>(
  (ref) => P2pEnabledNotifier(ref),
);

// ── Web companion (server-only mode) ────────────────────────────────────────

/// Manages starting/stopping the HTTP server for the web companion
/// independently of the LAN sync toggle.
///
/// The server is started when "Open on Laptop" is opened and stopped when the
/// screen is closed (if LAN sync is not separately active).
class WebCompanionNotifier extends StateNotifier<bool> {
  WebCompanionNotifier(this._ref) : super(false);

  final Ref _ref;

  Future<void> ensureStarted() async {
    // If the full LAN sync coordinator is already running we just piggyback.
    if (P2pCoordinator.instance.serverPort != null) {
      if (mounted) state = true;
      return;
    }
    if (state) return;
    try {
      final db       = await DatabaseHelper.instance.database;
      await _ref.read(identityInitProvider.future);
      final identity = await _ref.read(identityServiceProvider.future);
      final settings = _ref.read(settingsRepositoryProvider);
      final name     = await settings.get(SettingsKeys.ownerName);
      await WebCompanionService.instance.prewarmWebUi();
      await P2pCoordinator.instance.startServerOnly(
        db:          db,
        identity:    identity,
        displayName: (name == null || name.trim().isEmpty) ? 'KashCube' : name.trim(),
      );
      if (mounted) state = true;
    } catch (e) {
      debugPrint('[WebCompanion] ensureStarted() failed: $e');
    }
  }

  Future<void> stop() async {
    await P2pCoordinator.instance.stopServerOnly();
    if (mounted) state = false;
  }
}

final webCompanionProvider =
    StateNotifierProvider<WebCompanionNotifier, bool>(
  (ref) => WebCompanionNotifier(ref),
);

// ── HTTP Server Auto-Init ───────────────────────────────────────────────────

/// Automatically starts the HTTP server once at app launch.
///
/// The server persists for the entire app lifetime, ensuring that
/// endpoints like /health remain accessible globally (not just when
/// the "Open on Laptop" screen is visible). Non-fatal if server fails
/// to start (e.g., port already in use); "Open on Laptop" screen can
/// retry via ensureStarted().
final httpServerInitProvider = FutureProvider<void>((ref) async {
  try {
    final db       = await DatabaseHelper.instance.database;
    await ref.read(identityInitProvider.future);
    final identity = await ref.read(identityServiceProvider.future);
    final settings = ref.read(settingsRepositoryProvider);
    final name     = await settings.get(SettingsKeys.ownerName);
    
    await P2pCoordinator.instance.startServerOnly(
      db:          db,
      identity:    identity,
      displayName: (name == null || name.trim().isEmpty) ? 'KashCube' : name.trim(),
    );
    debugPrint('[HttpServerInit] Server started on port ${P2pServer.instance.port}');
  } catch (e) {
    debugPrint('[HttpServerInit] Failed to start server: $e');
    // Non-fatal — allows app to continue; /health can be retried later.
  }
});

// ── Diagnostics ─────────────────────────────────────────────────────────────

/// Live mDNS event log — replays current entries then streams updates.
final p2pDiscoveryLogProvider = StreamProvider<List<String>>((ref) async* {
  yield P2pDiscoveryService.instance.currentLog;
  yield* P2pDiscoveryService.instance.logStream;
});

/// Live HTTP request log from the embedded P2pServer.
final p2pServerLogProvider = StreamProvider<List<String>>((ref) async* {
  yield P2pServer.instance.currentHttpLog;
  yield* P2pServer.instance.httpLogStream;
});

/// Emits `true` each time a browser successfully authenticates with the phone.
/// Use [ref.listen] to fire analytics or update UI — never replays past events.
final browserConnectionEventProvider = StreamProvider.autoDispose<bool>((ref) {
  return P2pCoordinator.instance.browserConnectionStream;
});

/// Local IPv4 address of this device (null if unavailable).
final p2pLocalIpProvider = FutureProvider<String?>((ref) =>
    P2pDiscoveryService.getLocalIp());
