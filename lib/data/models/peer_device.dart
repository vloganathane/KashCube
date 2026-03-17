/// A KashCube device discovered on the local network via mDNS (Bonsoir).
///
/// This is an ephemeral, in-memory model — not persisted to SQLite.
/// Once the user completes pairing, a [TrustedPeer] row is written instead.
class PeerDevice {
  const PeerDevice({
    required this.identityId,
    required this.displayName,
    required this.host,
    required this.port,
    this.businessName,
    this.isTrusted = false,
    this.isReachable = true,
    this.lastSeenAt,
  });

  /// Permanent UUID from the remote device's `my_identity` row.
  final String identityId;

  /// Human-readable device/user name received in the mDNS TXT record.
  final String displayName;

  /// IP address (v4 or v6) resolved by Bonsoir.
  final String host;

  /// TCP port the remote shelf HTTP server is listening on.
  final int port;

  /// Business name from the TXT record (optional).
  final String? businessName;

  /// True if a [TrustedPeer] row exists for this `identityId`.
  final bool isTrusted;

  /// False if a recent ping timed out.
  final bool isReachable;

  final DateTime? lastSeenAt;

  /// Base URL for HTTP requests to this peer.
  String get baseUrl => 'http://$host:$port';

  PeerDevice copyWith({
    String? displayName,
    String? host,
    int? port,
    String? businessName,
    bool? isTrusted,
    bool? isReachable,
    DateTime? lastSeenAt,
  }) =>
      PeerDevice(
        identityId:   identityId,
        displayName:  displayName ?? this.displayName,
        host:         host ?? this.host,
        port:         port ?? this.port,
        businessName: businessName ?? this.businessName,
        isTrusted:    isTrusted ?? this.isTrusted,
        isReachable:  isReachable ?? this.isReachable,
        lastSeenAt:   lastSeenAt ?? this.lastSeenAt,
      );

  @override
  bool operator ==(Object other) =>
      other is PeerDevice && other.identityId == identityId;

  @override
  int get hashCode => identityId.hashCode;

  @override
  String toString() =>
      'PeerDevice($identityId, $displayName, $host:$port, trusted=$isTrusted)';
}
