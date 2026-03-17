import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../models/discovered_primary.dart';

/// Wraps the `bonsoir` package for mDNS service advertisement (primary device)
/// and discovery (secondary device).
///
/// Service type: `_kashcube._tcp`
///
/// TXT record attributes embedded in the advertisement:
///   `device_id`    — primary's permanent device UUID
///   `display_name` — human-readable name (e.g. "Navneet's Galaxy Tab")
///   `role`         — always "primary"
///
/// Usage on primary:
/// ```dart
/// await LanDiscoveryService.instance.startServer(
///   port,
///   displayName: 'Navneet\'s Tab',
///   deviceId: deviceId,
/// );
/// // ...
/// await LanDiscoveryService.instance.stopServer();
/// ```
///
/// Usage on secondary:
/// ```dart
/// await LanDiscoveryService.instance.startDiscovery(
///   onFound: (primary) {
///     print('Found ${primary.label} at ${primary.ipAddress}:${primary.port}');
///   },
/// );
/// // ...
/// await LanDiscoveryService.instance.stopDiscovery();
/// ```
class LanDiscoveryService {
  LanDiscoveryService._();
  static final LanDiscoveryService instance = LanDiscoveryService._();

  static const String _serviceType = '_kashcube._tcp';

  BonsoirBroadcast?   _broadcast;
  BonsoirDiscovery?   _discovery;
  StreamSubscription? _discoverySubscription;

  // ── Primary: advertise ───────────────────────────────────────────────────

  /// Registers the mDNS service so nearby secondaries can discover this device.
  ///
  /// [displayName] and [deviceId] are embedded in the TXT record so secondaries
  /// can show the device name before pairing completes.
  Future<void> startServer(
    int port, {
    String? displayName,
    String? deviceId,
  }) async {
    if (_broadcast != null) return; // already registered
    debugPrint('[DeviceLink] LanDiscovery.startServer: port=$port, displayName=$displayName, deviceId=$deviceId');

    final attrs = <String, String>{
      'role': 'primary',
      if (deviceId    != null) 'device_id':    deviceId,
      if (displayName != null) 'display_name': displayName,
    };

    final service = BonsoirService(
      name:       displayName ?? 'KashCube',
      type:       _serviceType,
      port:       port,
      attributes: attrs,
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();
    debugPrint('[DeviceLink] LanDiscovery.startServer: mDNS broadcast started OK');
  }

  /// Unregisters the mDNS service.
  Future<void> stopServer() async {
    if (_broadcast == null) return;
    await _broadcast!.stop();
    _broadcast = null;
    debugPrint('[DeviceLink] LanDiscovery.stopServer: mDNS broadcast stopped');
  }

  // ── Secondary: discover ──────────────────────────────────────────────────

  /// Starts mDNS discovery.
  ///
  /// [onFound] is called with a [DiscoveredPrimary] for every resolved
  /// `_kashcube._tcp` service, including the primary's display name and
  /// device ID from its TXT record attributes.
  ///
  /// [onLost] is called with the service name if a previously found primary
  /// goes offline.
  Future<void> startDiscovery({
    required void Function(DiscoveredPrimary device) onFound,
    void Function(String serviceName)? onLost,
  }) async {
    if (_discovery != null) return; // already discovering
    debugPrint('[DeviceLink] LanDiscovery.startDiscovery: starting mDNS discovery...');

    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.ready;
    await _discovery!.start();
    debugPrint('[DeviceLink] LanDiscovery.startDiscovery: mDNS discovery started, listening for _kashcube._tcp services');

    _discoverySubscription = _discovery!.eventStream?.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final svc = event.service;
        if (svc is! ResolvedBonsoirService) return;
        final host  = svc.host;
        if (host == null) return; // resolution failed — no IP address yet
        final port  = svc.port;
        final attrs = svc.attributes;
        debugPrint('[DeviceLink] LanDiscovery: service resolved — "${svc.name}" at $host:$port attrs=$attrs');
        onFound(DiscoveredPrimary(
          ipAddress:   host,
          port:        port,
          displayName: attrs['display_name'],
          deviceId:    attrs['device_id'],
          serviceName: svc.name,
        ));
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        debugPrint('[DeviceLink] LanDiscovery: service lost — ${event.service?.name}');
        onLost?.call(event.service?.name ?? '');
      }
    });
  }

  /// Stops mDNS discovery.
  Future<void> stopDiscovery() async {
    if (_discovery == null) return;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    await _discovery!.stop();
    _discovery = null;
  }

  bool get isRegistered  => _broadcast != null;
  bool get isDiscovering => _discovery != null;
}
