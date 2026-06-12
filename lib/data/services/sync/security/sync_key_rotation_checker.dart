import 'sync_key_rotation_policy.dart';

/// The result of evaluating the rotation status for a single trusted peer's
/// shared HMAC signing key.
class SyncKeyRotationResult {
  const SyncKeyRotationResult({
    required this.peerIdentityId,
    required this.keyVersion,
    required this.keyAgeDays,
    required this.status,
  });

  /// The `peer_identity_id` from the `trusted_peers` row.
  final String peerIdentityId;

  /// The current `key_version` for this peer (1-based epoch counter).
  final int keyVersion;

  /// The key age expressed in whole days, computed from the most recent
  /// rotation timestamp or — for unrotated keys — the original pairing time.
  final int keyAgeDays;

  /// The policy evaluation result.
  final SyncKeyRotationStatus status;
}

/// Evaluates the key rotation status for trusted peer rows from the
/// `trusted_peers` SQLite table.
///
/// Reads are performed against plain `Map<String, dynamic>` rows returned by
/// the database so this class has no direct sqflite dependency and can be
/// tested without platform channels.
///
/// Expected row keys:
/// - `peer_identity_id` (String, required)
/// - `paired_at` (String ISO-8601, required — used for unrotated keys)
/// - `key_version` (int, optional — defaults to 1 for legacy rows)
/// - `key_rotated_at` (String ISO-8601, optional — replaces `paired_at` when
///   a rotation has occurred)
///
/// The [now] parameter is injectable for deterministic testing.
class SyncKeyRotationChecker {
  const SyncKeyRotationChecker({
    required this.policy,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  final SyncKeyRotationPolicy policy;
  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Evaluates the rotation status for a single trusted peer row.
  ///
  /// Returns a [SyncKeyRotationResult] containing the computed key age and
  /// the [SyncKeyRotationStatus] determined by the injected [policy].
  ///
  /// If [peerRow] is missing the required `paired_at` / `peer_identity_id`
  /// fields the result has `keyAgeDays = 0` and a version of 1. This is a
  /// safe fallback: the policy still runs and callers can decide how to handle
  /// the malformed row.
  SyncKeyRotationResult evaluatePeerRow(Map<String, dynamic> peerRow) {
    final peerIdentityId = (peerRow['peer_identity_id'] as String?) ?? '';

    // key_version defaults to 1 for rows pre-dating the v85 migration.
    final keyVersion = (peerRow['key_version'] as int?) ?? 1;

    // Prefer key_rotated_at; fall back to paired_at for unrotated rows.
    final referenceTimeStr =
        (peerRow['key_rotated_at'] as String?) ??
        (peerRow['paired_at'] as String?);

    final referenceTime = referenceTimeStr != null
        ? DateTime.tryParse(referenceTimeStr)
        : null;

    final now = _clock();
    final keyAgeSeconds = referenceTime != null
        ? now.difference(referenceTime.toUtc()).inSeconds.clamp(0, (1 << 53))
        : 0;

    final status = policy.evaluate(
      keyVersion: keyVersion,
      keyAgeSeconds: keyAgeSeconds,
    );

    return SyncKeyRotationResult(
      peerIdentityId: peerIdentityId,
      keyVersion: keyVersion,
      keyAgeDays: keyAgeSeconds ~/ 86400,
      status: status,
    );
  }

  /// Evaluates all peers in [peerRows], returning one result per row.
  ///
  /// Rows that require or recommend rotation are not filtered out — callers
  /// decide the response. This allows a single query result to be audited
  /// in one pass.
  List<SyncKeyRotationResult> evaluateAll(
    List<Map<String, dynamic>> peerRows,
  ) => peerRows.map(evaluatePeerRow).toList(growable: false);
}
