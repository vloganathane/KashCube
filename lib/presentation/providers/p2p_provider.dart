import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/peer_device.dart';
import '../../data/services/action_center_background_service.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/p2p/p2p_coordinator.dart';
import '../../data/services/p2p/p2p_discovery_service.dart';
import '../providers/identity_provider.dart';
import '../providers/settings_provider.dart';

// ── Read-only stream providers ─────────────────────────────────────────────

/// Live list of peers currently visible on the LAN via mDNS.
final p2pPeersProvider = StreamProvider<List<PeerDevice>>((ref) =>
    P2pDiscoveryService.instance.peersStream);

/// Current coordinator status (phase, peer name, progress message).
final p2pSyncStatusProvider = StreamProvider<SyncStatus>((ref) =>
    P2pCoordinator.instance.statusStream);

// ── Enabled toggle (starts / stops the coordinator) ────────────────────────

/// Manages whether LAN sync is active.
///
/// Calling [P2pEnabledNotifier.enable] starts [P2pCoordinator] and registers
/// the WorkManager probe task.  [disable] reverses both.
class P2pEnabledNotifier extends StateNotifier<bool> {
  P2pEnabledNotifier(this._ref) : super(false);

  final Ref _ref;

  Future<void> enable() async {
    if (state) return;
    try {
      final db       = await DatabaseHelper.instance.database;
      final identity = await _ref.read(identityServiceProvider.future);
      final settings = _ref.read(settingsRepositoryProvider);
      final name     = await settings.get(SettingsKeys.ownerName);
      await P2pCoordinator.instance.start(
        db:          db,
        identity:    identity,
        displayName: (name == null || name.trim().isEmpty) ? 'KashCube' : name.trim(),
      );
      await registerP2pSyncTask();
      if (mounted) state = true;
    } catch (e) {
      // Non-fatal — coordinator may already be running or mDNS unavailable.
    }
  }

  Future<void> disable() async {
    if (!state) return;
    await P2pCoordinator.instance.stop();
    await cancelP2pSyncTask();
    if (mounted) state = false;
  }
}

final p2pEnabledProvider =
    StateNotifierProvider<P2pEnabledNotifier, bool>(
  (ref) => P2pEnabledNotifier(ref),
);
