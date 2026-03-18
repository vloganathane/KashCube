import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../../models/peer_device.dart';

/// mDNS service type advertised and scanned for KashCube P2P sync.
const _kServiceType = '_kashcube._tcp';

/// TXT record key names embedded in the mDNS advertisement.
const _kKeyIdentityId   = 'identity_id';
const _kKeyDisplayName  = 'display_name';
const _kKeyBusinessName = 'business_name';
const _kKeyVersion      = 'kc_version'; // for future protocol negotiation

/// Manages mDNS broadcast (server role) and discovery (client role) for
/// KashCube P2P LAN sync.
///
/// - Call [startBroadcast] when the HTTP server is up.
/// - Call [startDiscovery] to populate the found-devices list in the UI.
/// - Both can run simultaneously on the same device.
/// - All operations are platform-native via Bonsoir (Android NSD / iOS Bonjour).
/// - No network calls — 100% local LAN.
class P2pDiscoveryService {
  P2pDiscoveryService._();
  static final P2pDiscoveryService instance = P2pDiscoveryService._();

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  // Peers indexed by identityId for O(1) lookup during updates/removals.
  final _peers = <String, PeerDevice>{};
  final _peersController = StreamController<List<PeerDevice>>.broadcast();

  /// Live stream of currently visible peers on the LAN.
  Stream<List<PeerDevice>> get peersStream => _peersController.stream;

  /// Current snapshot (does not wait for first emission).
  List<PeerDevice> get currentPeers => List.unmodifiable(_peers.values);

  // ── Broadcast (server) ───────────────────────────────────────────────────

  /// Starts advertising this device on the LAN so peers can discover it.
  ///
  /// [identityId]   : `my_identity.identity_id`
  /// [displayName]  : user-facing device name
  /// [port]         : port the shelf HTTP server is listening on
  /// [businessName] : optional active business name for the TXT record
  Future<void> startBroadcast({
    required String identityId,
    required String displayName,
    required int port,
    String? businessName,
  }) async {
    await stopBroadcast();

    final service = BonsoirService(
      name: 'KashCube-$identityId',
      type: _kServiceType,
      port: port,
      attributes: {
        _kKeyIdentityId:   identityId,
        _kKeyDisplayName:  displayName,
        // ignore: use_null_aware_elements
        if (businessName != null) _kKeyBusinessName: businessName,
        _kKeyVersion: '1',
      },
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();
    debugPrint('[P2P] Broadcasting on port $port as "$displayName"');
  }

  Future<void> stopBroadcast() async {
    if (_broadcast != null) {
      await _broadcast!.stop();
      _broadcast = null;
      debugPrint('[P2P] Broadcast stopped');
    }
  }

  // ── Discovery (client) ───────────────────────────────────────────────────

  /// Starts scanning the LAN for other KashCube installations.
  ///
  /// [localIdentityId] : own identity — used to skip self-advertisement.
  /// [onTrusted]       : callback that returns true if a given identityId has
  ///                     an active [TrustedPeer] row (for UI labelling).
  Future<void> startDiscovery({
    required String localIdentityId,
    bool Function(String identityId)? onTrusted,
  }) async {
    await stopDiscovery();

    _discovery = BonsoirDiscovery(type: _kServiceType);
    await _discovery!.ready;

    _discovery!.eventStream!.listen(
      (event) => _handleEvent(event, localIdentityId, onTrusted),
      onError: (e) => debugPrint('[P2P] Discovery error: $e'),
    );

    await _discovery!.start();
    // Immediately emit the current (empty) peer list so StreamProvider
    // subscribers exit the loading state even when no peers are nearby yet.
    _emit();
    debugPrint('[P2P] Discovery started');
  }

  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await _discovery!.stop();
      _discovery = null;
      _peers.clear();
      _emit();
      debugPrint('[P2P] Discovery stopped');
    }
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _handleEvent(
    BonsoirDiscoveryEvent event,
    String localIdentityId,
    bool Function(String)? onTrusted,
  ) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        // Trigger resolution to get IP + TXT records.
        event.service?.resolve(_discovery!.serviceResolver);

      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        if (event.isServiceResolved) {
          _addOrUpdate(
            event.service as ResolvedBonsoirService,
            localIdentityId,
            onTrusted,
          );
        }

      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final id = event.service?.attributes[_kKeyIdentityId];
        if (id != null && _peers.remove(id) != null) {
          _emit();
          debugPrint('[P2P] Peer lost: $id');
        }

      default:
        break;
    }
  }

  void _addOrUpdate(
    ResolvedBonsoirService service,
    String localIdentityId,
    bool Function(String)? onTrusted,
  ) {
    final attrs      = service.attributes;
    final identityId = attrs[_kKeyIdentityId];
    if (identityId == null) return;        // malformed record
    if (identityId == localIdentityId) return; // our own broadcast

    final host = service.host ?? '';
    if (host.isEmpty) return; // not yet resolved

    final peer = PeerDevice(
      identityId:   identityId,
      displayName:  attrs[_kKeyDisplayName] ?? service.name,
      host:         host,
      port:         service.port,
      businessName: attrs[_kKeyBusinessName],
      isTrusted:    onTrusted?.call(identityId) ?? false,
      lastSeenAt:   DateTime.now(),
    );

    _peers[identityId] = peer;
    _emit();
    debugPrint('[P2P] Peer found/updated: $identityId @ $host:${service.port}');
  }

  void _emit() {
    if (!_peersController.isClosed) {
      _peersController.add(List.unmodifiable(_peers.values));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the OS-level device name using device_info_plus.
  static Future<String> getDeviceName() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return info.model;
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return info.name;
      } else if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return info.computerName;
      }
    } catch (_) {}
    return 'KashCube Device';
  }

  void dispose() {
    stopBroadcast();
    stopDiscovery();
    _peersController.close();
  }
}
