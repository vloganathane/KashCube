import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/libp2p_sync_repository_impl.dart';
import '../../data/repositories/webrtc_sync_repository_impl.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/libp2p/libp2p_discovery.dart';
import '../../data/services/libp2p/libp2p_node.dart';
import '../../data/services/libp2p/libp2p_protocol.dart';
import '../../domain/repositories/sync_repository.dart';
import 'settings_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
// libp2p Service Providers
// ════════════════════════════════════════════════════════════════════════════

/// Singleton instance of LibP2pNode (manages libp2p host lifecycle).
final libp2pNodeProvider = Provider<LibP2pNode>((_) => LibP2pNode());

/// Singleton instance of LibP2pProtocol (handles /kash-sync/1.0.0 frames).
final libp2pProtocolProvider = Provider<LibP2pProtocol>(
  (_) => LibP2pProtocol(),
);

/// Singleton instance of LibP2pDiscovery (mDNS peer discovery).
final libp2pDiscoveryProvider = Provider<LibP2pDiscovery>(
  (_) => LibP2pDiscovery(),
);

// ════════════════════════════════════════════════════════════════════════════
// Sync Repository Providers
// ════════════════════════════════════════════════════════════════════════════

/// WebRTC-based sync repository (legacy/current implementation).
///
/// Uses WebSocket (browser ↔ phone) or WebRTC DataChannel for transport.
/// This is the default sync implementation (Phase 0).
final webrtcSyncRepositoryProvider = Provider<SyncRepository>(
  (_) => WebRTCSyncRepositoryImpl(
    dbHelper: DatabaseHelper.instance,
    inboundDedupeCapacity: 512,
  ),
);

/// libp2p-based sync repository (experimental Phase 1 implementation).
///
/// Uses dart_libp2p for P2P sync over TCP/UDX with Noise encryption.
/// Implements /kash-sync/1.0.0 protocol with mDNS discovery (LAN-only).
final libp2pSyncRepositoryProvider = Provider<SyncRepository>(
  (ref) => Libp2pSyncRepositoryImpl(
    node: ref.watch(libp2pNodeProvider),
    protocol: ref.watch(libp2pProtocolProvider),
    discovery: ref.watch(libp2pDiscoveryProvider),
    dbHelper: DatabaseHelper.instance,
    inboundDedupeCapacity: 512,
  ),
);

/// Conditional sync repository provider (chooses WebRTC or libp2p based on feature flag).
///
/// **Default**: WebRTC (Phase 0 implementation)
/// **Experimental**: libp2p (Phase 1 implementation, enabled via [SettingsKeys.enableLibp2pSync])
///
/// **To enable libp2p**:
/// ```dart
/// await settingsRepo.set(SettingsKeys.enableLibp2pSync, 'true');
/// ```
///
/// **Feature flag**: `SettingsKeys.enableLibp2pSync` ('true' | 'false' | null)
/// - `null` or `'false'`: Use WebRTC (default)
/// - `'true'`: Use libp2p (experimental)
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  // Watch the libp2p setting and switch implementations dynamically
  final libp2pEnabled = ref.watch(libp2pSyncEnabledProvider);

  if (libp2pEnabled) {
    debugPrint('[SyncProvider] Using libp2p sync repository');
    return ref.watch(libp2pSyncRepositoryProvider);
  } else {
    debugPrint('[SyncProvider] Using WebRTC sync repository');
    return ref.watch(webrtcSyncRepositoryProvider);
  }
});

/// Future-based helper to determine which sync repository should be used.
///
/// This is a utility function for UI components to asynchronously determine
/// which provider to use based on the feature flag setting.
///
/// **Usage**:
/// ```dart
/// final useLibp2p = await shouldUseLibp2pSync(ref.read(settingsRepositoryProvider));
/// final syncRepo = useLibp2p
///   ? ref.read(libp2pSyncRepositoryProvider)
///   : ref.read(webrtcSyncRepositoryProvider);
/// ```
///
/// **Returns**: `true` if libp2p should be used, `false` for WebRTC (default).
Future<bool> shouldUseLibp2pSync(WidgetRef ref) async {
  final settingsRepo = ref.read(settingsRepositoryProvider);
  final enableLibp2p = await settingsRepo.get(SettingsKeys.enableLibp2pSync);
  return enableLibp2p == 'true';
}
