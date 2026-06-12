import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../app_logger.dart';
import '../../../core/constants/app_constants.dart';

import '../../models/peer_device.dart';

/// mDNS service type advertised and scanned for KashCube P2P sync.
const _kServiceType = '_kashcube._tcp';

/// TXT record key names embedded in the mDNS advertisement.
const _kKeyIdentityId = 'identity_id';
const _kKeyDisplayName = 'display_name';
const _kKeyBusinessName = 'business_name';
const _kKeyVersion = 'kc_version'; // for future protocol negotiation

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

  // Guards to prevent concurrent start calls from racing through the stop→create→start sequence.
  bool _startingBroadcast = false;
  bool _startingDiscovery = false;

  // Periodically probes each known peer's /hello endpoint to evict stale
  // entries that linger after the remote app is killed without sending a
  // mDNS goodbye packet.
  Timer? _stalenessTimer;
  static const _kProbeInterval = Duration(seconds: 30);
  static const _kProbeTimeout = Duration(seconds: 4);
  static const _kProbeFailureThreshold = 3;
  static const _kLegacyScanDelay = Duration(seconds: 2);
  static const _kLegacyProbeTimeout = Duration(milliseconds: 900);
  static const _kLegacyScanBatchSize = 24;

  Timer? _legacyScanTimer;
  bool _legacyScanInFlight = false;

  // Track consecutive probe failures per identity to avoid evicting healthy
  // peers on one transient timeout/jitter event.
  final _probeFailureCounts = <String, int>{};

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
    if (_startingBroadcast) return;
    _startingBroadcast = true;
    try {
      await stopBroadcast();

      final service = BonsoirService(
        name: 'KashCube-$identityId',
        type: _kServiceType,
        port: port,
        attributes: {
          _kKeyIdentityId: identityId,
          _kKeyDisplayName: displayName,
          // ignore: use_null_aware_elements
          if (businessName != null) _kKeyBusinessName: businessName,
          _kKeyVersion: '1',
        },
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.ready;
      await _broadcast!.start();
      _logEvent('BROADCAST started  name="$displayName"  port=$port');
    } finally {
      _startingBroadcast = false;
    }
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
    if (_startingDiscovery) return;
    _startingDiscovery = true;
    try {
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

      // Start the staleness prober.  Android NSD does not send a mDNS goodbye
      // packet when the remote app is force-killed, so `discoveryServiceLost`
      // never fires.  We compensate by probing each known peer's /hello every
      // 30 seconds and evicting any that fail to respond.
      _stalenessTimer?.cancel();
      _stalenessTimer = Timer.periodic(
        _kProbeInterval,
        (_) => _probeAllPeers(),
      );

      // LocalSend-style fallback: if multicast yields no peers shortly after
      // start, run a lightweight /24 HTTP probe on the default port.
      _legacyScanTimer?.cancel();
      _legacyScanTimer = Timer(_kLegacyScanDelay, () {
        if (_peers.isEmpty) {
          unawaited(_runLegacyHttpScan(localIdentityId, onTrusted));
        }
      });
    } finally {
      _startingDiscovery = false;
    }
  }

  Future<void> stopDiscovery() async {
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _legacyScanTimer?.cancel();
    _legacyScanTimer = null;
    if (_discovery != null) {
      await _discovery!.stop();
      _discovery = null;
      _peers.clear();
      _probeFailureCounts.clear();
      _emit();
      _logEvent('DISCOVERY stopped');
    }
  }

  Future<void> _runLegacyHttpScan(
    String localIdentityId,
    bool Function(String identityId)? onTrusted,
  ) async {
    if (_legacyScanInFlight) return;
    _legacyScanInFlight = true;
    try {
      final localIp = await getLocalIp();
      if (localIp == null) {
        _logEvent('LEGACY scan skipped  reason=no_local_ip');
        return;
      }

      final octets = localIp.split('.');
      if (octets.length != 4) {
        _logEvent('LEGACY scan skipped  reason=non_ipv4  ip=$localIp');
        return;
      }

      final subnet = '${octets[0]}.${octets[1]}.${octets[2]}';
      final localHost = int.tryParse(octets[3]);
      if (localHost == null) {
        _logEvent('LEGACY scan skipped  reason=bad_ipv4  ip=$localIp');
        return;
      }

      _logEvent(
        'LEGACY scan start  subnet=$subnet.0/24  port=${AppConstants.p2pPort}',
      );

      final targets = <String>[];
      for (var i = 1; i <= 254; i++) {
        if (i == localHost) continue;
        targets.add('$subnet.$i');
      }

      var found = 0;
      for (var i = 0; i < targets.length; i += _kLegacyScanBatchSize) {
        final end = (i + _kLegacyScanBatchSize > targets.length)
            ? targets.length
            : i + _kLegacyScanBatchSize;
        final batch = targets.sublist(i, end);

        final results = await Future.wait(
          batch.map(
            (ip) => _probeLegacyTarget(
              ip: ip,
              localIdentityId: localIdentityId,
              port: AppConstants.p2pPort,
              onTrusted: onTrusted,
            ),
          ),
        );

        for (final peer in results.whereType<PeerDevice>()) {
          _peers[peer.identityId] = peer;
          found++;
          _emit();
          _logEvent(
            'LEGACY resolved  id=${peer.identityId}  '
            'name="${peer.displayName}"  addr=${peer.host}:${peer.port}',
          );
        }

        if (_discovery == null) break;
      }

      if (found == 0) {
        _logEvent('LEGACY scan complete  no peers found');
      } else {
        _logEvent('LEGACY scan complete  peers_found=$found');
      }
    } finally {
      _legacyScanInFlight = false;
    }
  }

  Future<PeerDevice?> _probeLegacyTarget({
    required String ip,
    required String? localIdentityId,
    required int port,
    required bool Function(String identityId)? onTrusted,
  }) async {
    final client = HttpClient()..connectionTimeout = _kLegacyProbeTimeout;

    try {
      final uri = Uri.parse('http://$ip:$port/discover');
      final request = await client.getUrl(uri).timeout(_kLegacyProbeTimeout);
      final response = await request.close().timeout(_kLegacyProbeTimeout);
      if (response.statusCode >= 400) return null;

      final body = await response
          .transform(const Utf8Decoder())
          .join()
          .timeout(_kLegacyProbeTimeout);
      final json = jsonDecode(body);
      if (json is! Map) return null;
      if (json['app'] != 'kashcube') return null;

      final identityId = json['identity_id'] as String?;
      final displayName = json['display_name'] as String?;
      final discoveredPort = (json['port'] as num?)?.toInt() ?? port;

      if (identityId == null || displayName == null) return null;
      if (localIdentityId != null && identityId == localIdentityId) return null;

      // Preserve existing peer on mDNS path if already present.
      final existing = _peers[identityId];
      if (existing != null) {
        return existing.copyWith(
          host: ip,
          port: discoveredPort,
          displayName: displayName,
          isTrusted: onTrusted?.call(identityId) ?? existing.isTrusted,
          lastSeenAt: DateTime.now(),
        );
      }

      return PeerDevice(
        identityId: identityId,
        displayName: displayName,
        host: ip,
        port: discoveredPort,
        isTrusted: onTrusted?.call(identityId) ?? false,
        lastSeenAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Manual fallback discovery for a known target IP/port.
  ///
  /// This probes `/discover` and, on success, merges the discovered device
  /// into the same in-memory peer list used by mDNS discovery.
  Future<PeerDevice?> discoverManualTarget({
    required String ip,
    required int port,
    String? localIdentityId,
    bool Function(String identityId)? onTrusted,
  }) async {
    final peer = await _probeLegacyTarget(
      ip: ip,
      localIdentityId: localIdentityId,
      port: port,
      onTrusted: onTrusted,
    );
    if (peer == null) {
      _logEvent('MANUAL discover failed  target=$ip:$port');
      return null;
    }

    _peers[peer.identityId] = peer;
    _emit();
    _logEvent(
      'MANUAL discovered  id=${peer.identityId}  '
      'name="${peer.displayName}"  addr=${peer.host}:${peer.port}',
    );
    return peer;
  }

  /// Probes every currently-tracked peer's `/hello` endpoint.
  /// Peers that fail (connection refused, timeout, wrong app) are evicted.
  void _probeAllPeers() {
    // Snapshot the current peer list to avoid concurrent-modification issues.
    final snapshot = Map<String, PeerDevice>.from(_peers);
    for (final entry in snapshot.entries) {
      _probePeer(entry.key, entry.value);
    }
  }

  Future<void> _probePeer(String identityId, PeerDevice peer) async {
    final client = HttpClient()..connectionTimeout = _kProbeTimeout;
    try {
      final uri = Uri.parse('http://${peer.host}:${peer.port}/hello');
      final request = await client.getUrl(uri).timeout(_kProbeTimeout);
      final response = await request.close().timeout(_kProbeTimeout);
      final body = await response
          .transform(const Utf8Decoder())
          .join()
          .timeout(_kProbeTimeout);

      if (response.statusCode >= 400) {
        _evictStalePeer(
          identityId,
          peer,
          'hello status ${response.statusCode}',
        );
        return;
      }

      final json = jsonDecode(body);
      if (json is! Map || json['app'] != 'kashcube') {
        _evictStalePeer(identityId, peer, 'unexpected hello body');
        _probeFailureCounts.remove(identityId);
        return;
      }
      // Peer is alive — update lastSeenAt.
      final updated = peer.copyWith(lastSeenAt: DateTime.now());
      _peers[identityId] = updated;
      _probeFailureCounts.remove(identityId);
    } catch (e) {
      // Any error (connection refused, timeout, socket exception) means the
      // server might be unreachable. We only evict after repeated failures to
      // tolerate transient LAN hiccups.
      AppLogger.instance.debug(
        'Peer probe failed',
        category: 'p2p_discovery',
        error: e,
      );
      final failures = (_probeFailureCounts[identityId] ?? 0) + 1;
      _probeFailureCounts[identityId] = failures;
      _logEvent(
        'PROBE failed  id=$identityId  name="${peer.displayName}"  '
        'count=$failures/$_kProbeFailureThreshold',
      );
      if (failures >= _kProbeFailureThreshold) {
        _evictStalePeer(identityId, peer, 'probe failed x$failures');
        _probeFailureCounts.remove(identityId);
      }
    } finally {
      client.close(force: true);
    }
  }

  void _evictStalePeer(String identityId, PeerDevice peer, String reason) {
    if (_peers.remove(identityId) != null) {
      _probeFailureCounts.remove(identityId);
      _emit();
      _logEvent(
        'EVICTED stale peer  id=$identityId  name="${peer.displayName}"  reason=$reason',
      );
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
          _probeFailureCounts.remove(id);
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
    final attrs = service.attributes;
    final identityId = attrs[_kKeyIdentityId];
    if (identityId == null) return; // malformed record
    if (identityId == localIdentityId) {
      _logEvent('SKIPPED self  id=$identityId');
      return;
    }

    final rawHost = service.host ?? '';
    if (rawHost.isEmpty) return; // not yet resolved

    // Bonsoir on Android returns the mDNS hostname (e.g. "Android_XXXX.local.")
    // instead of the IP address. InternetAddress.tryParse() returns null for
    // hostnames, so we detect that case and resolve asynchronously.
    if (InternetAddress.tryParse(rawHost) != null) {
      // Already an IP — store immediately.
      _storePeer(
        service: service,
        identityId: identityId,
        host: rawHost,
        onTrusted: onTrusted,
      );
    } else {
      // Hostname — resolve to IP via mDNS/DNS, then store.
      // Store with the hostname first so the peer is visible while resolving.
      _storePeer(
        service: service,
        identityId: identityId,
        host: rawHost,
        onTrusted: onTrusted,
      );
      _resolveHostname(
        service: service,
        identityId: identityId,
        hostname: rawHost,
        onTrusted: onTrusted,
      );
    }
  }

  void _storePeer({
    required ResolvedBonsoirService service,
    required String identityId,
    required String host,
    required bool Function(String)? onTrusted,
  }) {
    final attrs = service.attributes;
    final peer = PeerDevice(
      identityId: identityId,
      displayName: attrs[_kKeyDisplayName] ?? service.name,
      host: host,
      port: service.port,
      businessName: attrs[_kKeyBusinessName],
      isTrusted: onTrusted?.call(identityId) ?? false,
      lastSeenAt: DateTime.now(),
    );
    _peers[identityId] = peer;
    _emit();
    _logEvent(
      'RESOLVED  id=$identityId  name="${peer.displayName}"  addr=$host:${service.port}  trusted=${peer.isTrusted}',
    );
  }

  /// Performs an async DNS/mDNS lookup for [hostname] and, if successful,
  /// upgrades the stored [PeerDevice] with the resolved IPv4 address.
  Future<void> _resolveHostname({
    required ResolvedBonsoirService service,
    required String identityId,
    required String hostname,
    required bool Function(String)? onTrusted,
  }) async {
    try {
      // Strip trailing dot from mDNS FQDN ("foo.local." → "foo.local")
      final lookup = hostname.endsWith('.')
          ? hostname.substring(0, hostname.length - 1)
          : hostname;
      final addresses = await InternetAddress.lookup(
        lookup,
        type: InternetAddressType.IPv4,
      );
      if (addresses.isEmpty) return;

      final ip = addresses.first.address;
      // Only update if the peer is still tracked (it may have been lost).
      if (!_peers.containsKey(identityId)) return;

      _storePeer(
        service: service,
        identityId: identityId,
        host: ip,
        onTrusted: onTrusted,
      );
      _logEvent('RESOLVED-IP  id=$identityId  hostname=$hostname  ip=$ip');
    } catch (e) {
      debugPrint('[P2P] hostname lookup failed for $hostname: $e');
    }
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
    final n = DateTime.now();
    final ts =
        '${n.hour.toString().padLeft(2, '0')}:'
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

  /// Returns the LAN IPv4 address of this device, preferring the interface
  /// that a companion device (laptop/tablet) can actually reach.
  ///
  /// Android exposes interfaces in arbitrary order; the priority ladder ensures
  /// the best reachable address is chosen:
  ///
  /// Priority:
  ///   1. `wlan*`   — Wi-Fi client OR hotspot AP when phone is NOT on a Wi-Fi
  ///                  router (single-chip phones use `wlan0` in AP mode).
  ///   2. `en*`     — Wi-Fi / Ethernet (iOS / macOS)
  ///   3. `ap*`     — Dedicated hotspot AP interface (dual-virtual-NIC phones,
  ///                  e.g. some MediaTek/Qualcomm devices running Android 10+).
  ///   4. `rndis*`  — USB tethering (phone as USB hotspot to a PC).
  ///   5. Any other non-loopback, non-virtual IPv4 (emulator fallback).
  ///   90. `tun*`, `tap*`, `rmnet*`, `p2p*` — VPN / cellular / Wi-Fi Direct.
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      // Build a list of (priority, address) pairs and return the best one.
      // Lower priority number = preferred.
      String? best;
      int bestPriority = 99;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        int priority;
        if (name.startsWith('wlan')) {
          priority = 0; // Android Wi-Fi client or Wi-Fi hotspot (single-chip)
        } else if (name.startsWith('en')) {
          priority = 1; // iOS/macOS Wi-Fi or Ethernet
        } else if (name.startsWith('ap')) {
          priority = 3; // Android dedicated hotspot AP virtual interface
        } else if (name.startsWith('rndis')) {
          priority = 4; // USB tethering — phone acting as USB hotspot
        } else if (name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('rmnet') ||
            name.startsWith('p2p')) {
          priority = 90; // VPN / cellular / Wi-Fi Direct — avoid
        } else {
          priority = 50; // Unknown — accept as last resort
        }

        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          debugPrint(
            '[getLocalIp] iface=${iface.name} addr=${addr.address} '
            'loopback=${addr.isLoopback} priority=$priority '
            '(current best: $best @ $bestPriority)',
          );
          if (priority < bestPriority) {
            bestPriority = priority;
            best = addr.address;
          }
        }
      }

      debugPrint('[getLocalIp] selected → $best (priority $bestPriority)');
      return best;
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to get local IP address',
        category: 'p2p_discovery',
        error: e,
      );
    }
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
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to get device name',
        category: 'p2p_discovery',
        error: e,
      );
    }
    return 'KashCube Device';
  }

  void dispose() {
    stopBroadcast();
    stopDiscovery();
    _peersController.close();
    _logController.close();
  }
}
