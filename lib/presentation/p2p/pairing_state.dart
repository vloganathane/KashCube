/// Phase of the peer pairing flow — drives the UI overlay on [PairScreen].
enum PairingPhase {
  /// Nothing happening. Camera and QR code shown normally.
  idle,

  /// Camera is live and scanning for a QR code.
  scanning,

  /// QR decoded; deriving the shared secret via HKDF.
  validating,

  /// HKDF done; writing the [TrustedPeer] row to the database.
  saving,

  /// Pairing completed successfully.
  success,

  /// Something went wrong — [PairingState.errorMessage] holds the reason.
  error,
}

/// Immutable snapshot of the pairing flow state.
class PairingState {
  const PairingState({required this.phase, this.peerName, this.errorMessage});

  final PairingPhase phase;

  /// Display name of the peer that was just paired (set on [PairingPhase.success]).
  final String? peerName;

  /// Human-readable error description (set on [PairingPhase.error]).
  final String? errorMessage;

  PairingState copyWith({
    PairingPhase? phase,
    String? peerName,
    String? errorMessage,
  }) => PairingState(
    phase: phase ?? this.phase,
    peerName: peerName ?? this.peerName,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  @override
  String toString() => 'PairingState($phase, peer=$peerName)';
}
