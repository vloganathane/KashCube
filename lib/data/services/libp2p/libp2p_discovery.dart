import 'dart:async';

import 'package:dart_libp2p/dart_libp2p.dart';
import 'package:dart_libp2p/p2p/discovery/mdns.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/repositories/sync_repository.dart';

/// Service type for KashCube mDNS discovery.
/// We use the standard libp2p service name for compatibility.
const String kashSyncServiceType = '_p2p._udp';

/// Service name for local device (generated randomly by dart_libp2p).
const String kashSyncServiceName = 'KashCube Sync';

/// mDNS-based peer discovery for libp2p nodes on local network.
///
/// Wraps dart_libp2p's MdnsDiscovery to broadcast and discover peers
/// on the same LAN. Emits discovered peers as [SyncPeer] objects compatible
/// with the SyncRepository interface.
///
/// How it works:
/// 1. Receives libp2p Host instance (created in LibP2pNode)
/// 2. Creates MdnsDiscovery using the Host
/// 3. Starts mDNS broadcasting and listening
/// 4. Implements MdnsNotifee callback to receive peer discoveries
/// 5. Converts AddrInfo (dart_libp2p) → SyncPeer (KashCube domain model)
///
/// Usage:
/// ```dart
/// final discovery = LibP2pDiscovery();
/// await discovery.start(host: node.host);
/// discovery.discoveredPeers.listen((peer) {
///   print('Found peer: ${peer.name}');
/// });
/// await discovery.stop();
/// ```
class LibP2pDiscovery implements MdnsNotifee {
  /// dart_libp2p mDNS discovery instance
  MdnsDiscovery? _mdnsDiscovery;

  /// Discovery state
  bool _isStarted = false;

  /// Controller for discovered peers
  final StreamController<SyncPeer> _discoveredPeers =
      StreamController<SyncPeer>.broadcast();

  /// Discovered peers stream (emits [SyncPeer] when peer found)
  Stream<SyncPeer> get discoveredPeers => _discoveredPeers.stream;

  /// Current discovery state
  bool get isStarted => _isStarted;

  // ────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  /// Start mDNS discovery and broadcasting.
  ///
  /// [host]: libp2p Host instance (from LibP2pNode.host getter)
  /// [metadata]: Optional metadata (currently unused, reserved for future use)
  ///
  /// Creates MdnsDiscovery using the provided Host and starts both:
  /// 1. Broadcasting local service (so others can find us)
  /// 2. Listening for peers (so we find others)
  ///
  /// Note: Port and multiaddr are extracted from Host automatically by MdnsDiscovery.
  /// The peerName parameter has been removed - dart_libp2p generates it randomly.
  Future<void> start({
    required Host host,
    Map<String, String>? metadata,
  }) async {
    if (_isStarted) {
      debugPrint('[LibP2pDiscovery] Already started');
      return;
    }

    try {
      debugPrint('[LibP2pDiscovery] Starting discovery...');

      // Create MdnsDiscovery using the Host
      _mdnsDiscovery = MdnsDiscovery(
        host,
        serviceName: kashSyncServiceType,
        notifee: this, // this class implements MdnsNotifee
      );

      // Start mDNS service (handles both broadcasting and listening)
      await _mdnsDiscovery!.start();

      _isStarted = true;
      debugPrint('[LibP2pDiscovery] Started successfully');
      debugPrint('[LibP2pDiscovery] Broadcasting as: ${host.id}');
      debugPrint('[LibP2pDiscovery] Listening on: ${host.addrs.map((a) => a.toString()).join(", ")}');
    } catch (e, stack) {
      debugPrint('[LibP2pDiscovery] Start failed: $e');
      debugPrint(stack.toString());
      await stop(); // Cleanup partial state
      rethrow; // Propagate error to caller
    }
  }

  /// Stop mDNS discovery and broadcasting.
  ///
  /// Gracefully stops MdnsDiscovery service.
  Future<void> stop() async {
    if (!_isStarted) return;

    debugPrint('[LibP2pDiscovery] Stopping...');

    try {
      // Stop mDNS discovery
      if (_mdnsDiscovery != null) {
        await _mdnsDiscovery!.stop();
        _mdnsDiscovery = null;
      }

      _isStarted = false;
      debugPrint('[LibP2pDiscovery] Stopped');
    } catch (e, stack) {
      debugPrint('[LibP2pDiscovery] Stop error: $e');
      debugPrint(stack.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // MdnsNotifee Implementation
  // ────────────────────────────────────────────────────────────────────────────

  /// Called by MdnsDiscovery when a peer is discovered.
  ///
  /// Converts dart_libp2p AddrInfo → KashCube SyncPeer domain model.
  @override
  void handlePeerFound(AddrInfo addrInfo) {
    try {
      final peerId = addrInfo.id.toString();
      debugPrint('[LibP2pDiscovery] Discovered peer: $peerId');

      // Extract first multiaddr (peers may have multiple addresses)
      final multiaddrs = addrInfo.addrs.map((addr) {
        // Append peer ID to multiaddr if not already present
        final addrStr = addr.toString();
        if (!addrStr.contains('/p2p/')) {
          return '$addrStr/p2p/$peerId';
        }
        return addrStr;
      }).toList();

      if (multiaddrs.isEmpty) {
        debugPrint('[LibP2pDiscovery] Peer has no addresses, skipping');
        return;
      }

      // Create SyncPeer object
      // TODO: Store multiaddr mapping in repository for connection dial
      // SyncPeer domain model doesn't have metadata field
      final peer = SyncPeer(
        peerId: peerId,
        displayName: 'KashCube Device', // TODO: Extract from metadata when available
        discoveredAt: DateTime.now(),
        deviceType: null, // Unknown device type
      );

      // Emit discovered peer
      _discoveredPeers.add(peer);

      debugPrint('[LibP2pDiscovery] Emitted peer: ${peer.displayName} ($peerId)');
      debugPrint('[LibP2pDiscovery] Multiaddrs: ${multiaddrs.join(", ")}');
    } catch (e, stack) {
      debugPrint('[LibP2pDiscovery] Error processing discovered peer: $e');
      debugPrint(stack.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

  /// Dispose resources.
  void dispose() {
    _discoveredPeers.close();
  }
}
