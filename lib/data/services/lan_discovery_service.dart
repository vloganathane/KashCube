import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

/// Wraps the `nsd` package for mDNS service registration (primary device)
/// and discovery (secondary device).
///
/// Service type: `_kashcube._tcp`
/// Service name: `KashCube`
///
/// Usage on primary:
/// ```dart
/// await LanDiscoveryService.instance.startServer(port);
/// // ... sync server running ...
/// await LanDiscoveryService.instance.stopServer();
/// ```
///
/// Usage on secondary:
/// ```dart
/// await LanDiscoveryService.instance.startDiscovery(onFound: (ip, port) { ... });
/// // ...
/// await LanDiscoveryService.instance.stopDiscovery();
/// ```
class LanDiscoveryService {
  LanDiscoveryService._();
  static final LanDiscoveryService instance = LanDiscoveryService._();

  static const String _serviceType = '_kashcube._tcp';
  static const String _serviceName = 'KashCube';

  nsd.Registration? _registration;
  nsd.Discovery?    _discovery;

  // ── Primary: register ────────────────────────────────────────────────────

  /// Registers the mDNS service so nearby secondaries can discover this device.
  Future<void> startServer(int port) async {
    if (_registration != null) return; // already registered
    _registration = await nsd.register(
      nsd.Service(name: _serviceName, type: _serviceType, port: port),
    );
  }

  /// Unregisters the mDNS service.
  Future<void> stopServer() async {
    if (_registration == null) return;
    await nsd.unregister(_registration!);
    _registration = null;
  }

  // ── Secondary: discover ──────────────────────────────────────────────────

  /// Starts mDNS discovery.  [onFound] is called for each discovered instance.
  /// [onLost] is called if a previously found service disappears.
  Future<void> startDiscovery({
    required void Function(String ip, int port, String serviceName) onFound,
    void Function(String serviceName)? onLost,
  }) async {
    if (_discovery != null) return; // already discovering
    _discovery = await nsd.startDiscovery(_serviceType);
    _discovery!.addServiceListener((service, status) {
      final name = service.name ?? _serviceName;
      final port = service.port;
      if (status == nsd.ServiceStatus.found) {
        final addresses = service.addresses;
        if (addresses != null && addresses.isNotEmpty && port != null) {
          // Prefer IPv4
          final addr = addresses.firstWhere(
            (a) => a.type == InternetAddressType.IPv4,
            orElse: () => addresses.first,
          );
          onFound(addr.address, port, name);
        }
      } else if (status == nsd.ServiceStatus.lost) {
        onLost?.call(name);
      }
    });
  }

  /// Stops mDNS discovery.
  Future<void> stopDiscovery() async {
    if (_discovery == null) return;
    await nsd.stopDiscovery(_discovery!);
    _discovery = null;
  }

  bool get isRegistered  => _registration != null;
  bool get isDiscovering => _discovery    != null;
}
