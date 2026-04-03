// Key rotation status and policy for the connect-anywhere sync security layer.
//
// Provides the rules that determine when a peer's shared HMAC signing key
// should be rotated. The policy is evaluated against the key's current version
// number and age, and returns one of three possible statuses:
//
// - SyncKeyRotationOk          — key is within acceptable age and version bounds
// - SyncKeyRotationRecommended — key is approaching its rotation threshold
// - SyncKeyRotationRequired    — key has exceeded a mandatory threshold and
//                                must be rotated before further sync traffic
//
// The policy objects and status types are intentionally pure-function
// (stateless, side-effect free) so they can be unit-tested without any
// database or platform dependencies.

/// Base class for key rotation evaluation results.
sealed class SyncKeyRotationStatus {
  const SyncKeyRotationStatus();
}

/// The current key is within all acceptable bounds — no action needed.
final class SyncKeyRotationOk extends SyncKeyRotationStatus {
  const SyncKeyRotationOk();
}

/// The current key is approaching a threshold — rotation is advisable but
/// sync traffic is still permitted.
final class SyncKeyRotationRecommended extends SyncKeyRotationStatus {
  const SyncKeyRotationRecommended({required this.reason});

  /// Human-readable explanation of why rotation is recommended.
  final String reason;
}

/// The current key has exceeded a mandatory threshold — rotation is required.
///
/// Implementations that enforce this status should refuse to sign or verify
/// sync frames until a new key is in place.
final class SyncKeyRotationRequired extends SyncKeyRotationStatus {
  const SyncKeyRotationRequired({required this.reason});

  /// Human-readable explanation of why rotation is required.
  final String reason;
}

/// Contract for key rotation policies.
///
/// A policy is a pure function: given the key's current [keyVersion] and its
/// [keyAgeSeconds], it returns the appropriate [SyncKeyRotationStatus].
abstract class SyncKeyRotationPolicy {
  const SyncKeyRotationPolicy();

  /// Evaluates the rotation status for a key.
  ///
  /// [keyVersion] is the monotonically increasing version counter stored in
  /// `trusted_peers.key_version`. A value of 1 means the original paired key.
  ///
  /// [keyAgeSeconds] is the elapsed time in seconds since the key was last
  /// rotated (or since initial pairing for unrotated keys).
  SyncKeyRotationStatus evaluate({
    required int keyVersion,
    required int keyAgeSeconds,
  });
}

/// Concrete time-and-version-based rotation policy.
///
/// Rotation is required when:
/// - [keyVersion] is below [minAcceptableVersion] (e.g. after a security
///   incident forces a minimum version floor), or
/// - [keyAgeSeconds] exceeds [maxKeyAgeDays] × 86 400
///
/// Rotation is recommended (but not mandatory) when:
/// - [keyAgeSeconds] exceeds [recommendRotationAfterDays] × 86 400
///
/// Defaults are conservative for a local-first app:
/// - 1 acceptable version minimum (all v1-and-above keys are valid)
/// - 30-day soft recommendation
/// - 90-day hard requirement
class DefaultSyncKeyRotationPolicy extends SyncKeyRotationPolicy {
  const DefaultSyncKeyRotationPolicy({
    this.minAcceptableVersion = 1,
    this.recommendRotationAfterDays = 30,
    this.maxKeyAgeDays = 90,
  }) : assert(
         recommendRotationAfterDays <= maxKeyAgeDays,
         'recommendRotationAfterDays must not exceed maxKeyAgeDays',
       );

  /// Keys with a version strictly below this number are considered invalid.
  final int minAcceptableVersion;

  /// Days after which rotation is recommended.
  final int recommendRotationAfterDays;

  /// Days after which rotation is mandatory.
  final int maxKeyAgeDays;

  @override
  SyncKeyRotationStatus evaluate({
    required int keyVersion,
    required int keyAgeSeconds,
  }) {
    // Version floor check — hard requirement, evaluated first.
    if (keyVersion < minAcceptableVersion) {
      return SyncKeyRotationRequired(
        reason: 'Key version $keyVersion is below the minimum acceptable '
            'version $minAcceptableVersion',
      );
    }

    final keyAgeDays = keyAgeSeconds ~/ 86400;

    // Mandatory age threshold.
    if (keyAgeDays > maxKeyAgeDays) {
      return SyncKeyRotationRequired(
        reason: 'Key is $keyAgeDays days old, exceeding the mandatory '
            'rotation threshold of $maxKeyAgeDays days',
      );
    }

    // Soft recommendation threshold.
    if (keyAgeDays > recommendRotationAfterDays) {
      return SyncKeyRotationRecommended(
        reason: 'Key is $keyAgeDays days old; rotation is recommended '
            'after $recommendRotationAfterDays days',
      );
    }

    return const SyncKeyRotationOk();
  }
}
