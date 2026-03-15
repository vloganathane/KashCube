/// A KashCube primary device discovered on the local network via mDNS.
///
/// Produced by [LanDiscoveryService.startDiscovery] when a running
/// `_kashcube._tcp` service is resolved (bonsoir `discoveryServiceResolved`
/// event).
///
/// The [displayName] and [deviceId] come from the service's TXT record
/// attributes, allowing the secondary device to show the primary's name
/// before pairing completes.
class DiscoveredPrimary {
  const DiscoveredPrimary({
    required this.ipAddress,
    required this.port,
    this.displayName,
    this.deviceId,
    this.serviceName,
  });

  /// Resolved IPv4 address of the primary device.
  final String ipAddress;

  /// TCP port the primary's [SyncServer] is bound to.
  final int port;

  /// Human-readable device name from the TXT record `display_name` attribute.
  /// Null if the primary is running an older build that didn't embed TXT records.
  final String? displayName;

  /// The primary's device UUID from the TXT record `device_id` attribute.
  final String? deviceId;

  /// Raw mDNS service name (used as a fallback display label).
  final String? serviceName;

  /// Best available label for display:
  /// TXT `display_name` → mDNS service name → IP address.
  String get label => displayName ?? serviceName ?? ipAddress;

  @override
  String toString() =>
      'DiscoveredPrimary(ip: $ipAddress, port: $port, label: $label)';
}
