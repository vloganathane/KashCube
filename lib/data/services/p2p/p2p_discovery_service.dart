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

  // Diagnostic event log — last 50 entries, newest at end.
  static const _kMaxLogEntries = 50;
  final _logEntries = <String>[];
  final _logController = StreamController<List<String>>.broadcast();

  /// Live stream of discovery/broadcast events for the diagnostics panel.
  Stream<List<String>> get logStream => _logController.stream;

  /// Current snapshot of the event log (newest at end).
  List<String> get currentLog => List.unmodifiable(_logEntries);

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
    _logEvent('BROADCAST started  name="$displayName"  port=$port');
  }

  Future<void> stopBroadcast() async {
    if (_broadcast != null) {
      await _broadcast!.stop();
      _broadcast = null;
      _logEvent('BROADCAST stopped');
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
    _logEvent('DISCOVERY started  type=$_kServiceType');
  }

  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await _discovery!.stop();
      _discovery = null;
      _peers.clear();
      _emit();
      _logEvent('DISCOVERY stopped');
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
        _logEvent('FOUND  name="${event.service?.name}"  (resolving…)');
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
          _logEvent('LOST  id=$id');
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
    if (identityId == localIdentityId) {
      _logEvent('SKIPPED self  id=$identityId');
      return;
    }

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
    _logEvent('RESOLVED  id=$identityId  name="${peer.displayName}"  addr=$host:${service.port}  trusted=${peer.isTrusted}');
  }

  void _emit() {
    if (!_peersController.isClosed) {
      _peersController.add(List.unmodifiable(_peers.values));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Records a diagnostic log entry, forwards it to [logStream], and
  /// calls [debugPrint] so it also appears in the IDE / adb logcat.
  void _logEvent(String message) {
    final n  = DateTime.now();
    final ts = '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
    final entry = '$ts  $message';
    _logEntries.add(entry);
    if (_logEntries.length > _kMaxLogEntries) _logEntries.removeAt(0);
    if (!_logController.isClosed) {
      _logController.add(List.unmodifiable(_logEntries));
    }
    debugPrint('[P2P] $message');
  }

  /// Returns the first non-loopback IPv4 address of this device, or null.
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

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
    _logController.close();
  }
}
