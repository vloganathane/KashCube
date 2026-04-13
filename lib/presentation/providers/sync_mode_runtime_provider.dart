import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/action_center_background_service.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/p2p/p2p_coordinator.dart';
import '../providers/identity_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_repository_provider.dart';

/// Runtime orchestration for LAN sync modes.
///
/// Keeps sync-mode branching (WebRTC vs libp2p) out of UI-facing providers.
/// This is the first step toward modularizing sync internals from app core.
class SyncModeRuntime {
  SyncModeRuntime(this._ref);

  final Ref _ref;

  Future<void> startLanSync() async {
    final db = await DatabaseHelper.instance.database;

    // Wait for both signing identity and identity_id used by coordinator.
    await _ref.read(identityInitProvider.future);
    final identity = await _ref.read(identityServiceProvider.future);
    final settings = _ref.read(settingsRepositoryProvider);
    final name = await settings.get(SettingsKeys.ownerName);
    final displayName = (name == null || name.trim().isEmpty)
        ? 'KashCube'
        : name.trim();

    final libp2pEnabled = _ref.read(libp2pSyncEnabledProvider);
    debugPrint(
      '[SyncRuntime] Sync mode: ${libp2pEnabled ? "libp2p (experimental)" : "WebRTC (legacy)"}',
    );

    if (libp2pEnabled) {
      debugPrint('[SyncRuntime] Initializing libp2p sync...');
      final syncRepo = _ref.read(libp2pSyncRepositoryProvider);
      await syncRepo.initialize();

      debugPrint('[SyncRuntime] ✅ libp2p sync initialized');
      debugPrint('[SyncRuntime] Peer ID: ${_ref.read(libp2pNodeProvider).localPeerId}');
      debugPrint(
        '[SyncRuntime] Listening on: ${_ref.read(libp2pNodeProvider).listeningAddrs.join(", ")}',
      );

      await registerP2pSyncTask();
      return;
    }

    debugPrint('[SyncRuntime] Using WebRTC sync (P2pCoordinator)');
    await P2pCoordinator.instance.start(
      db: db,
      identity: identity,
      displayName: displayName,
    );
    await registerP2pSyncTask();
  }

  Future<void> stopLanSync() async {
    final libp2pEnabled = _ref.read(libp2pSyncEnabledProvider);

    if (libp2pEnabled) {
      debugPrint('[SyncRuntime] Stopping libp2p sync...');
      final node = _ref.read(libp2pNodeProvider);
      await node.close();
      debugPrint('[SyncRuntime] ✅ libp2p sync stopped');
    } else {
      debugPrint('[SyncRuntime] Stopping WebRTC sync...');
      await P2pCoordinator.instance.stop();
    }

    await cancelP2pSyncTask();
  }
}

final syncModeRuntimeProvider = Provider<SyncModeRuntime>(
  (ref) => SyncModeRuntime(ref),
);
