import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'sync_signaling_messages.dart';

/// Contract for application-layer frame integrity on sync transport channels.
///
/// Implementations must be side-effect free: [sign] returns a new map with
/// an added integrity field; [verify] returns the original map without the
/// integrity field, or null when verification fails.
abstract class SyncFrameIntegrityChecker {
  const SyncFrameIntegrityChecker();

  /// Returns a copy of [frame] with an integrity proof added.
  ///
  /// Only data-plane eligible frames that carry financial payload are signed.
  /// Control-plane frames (auth, WebRTC signaling) are returned unchanged.
  Map<String, dynamic> sign(Map<String, dynamic> frame);

  /// Returns a verified copy of [frame] with the integrity field removed.
  ///
  /// Returns null if:
  /// - The frame carries a data-plane type and the integrity proof is absent.
  /// - The integrity proof is present but fails verification.
  /// - The frame is structurally unsound (missing type).
  ///
  /// Control-plane frames are returned unchanged (no proof expected).
  Map<String, dynamic>? verify(Map<String, dynamic> frame);
}

/// No-op implementation used in local-first builds and tests that do not
/// exercise the security path.
///
/// Both [sign] and [verify] return defensive copies of the frame without
/// adding or examining any integrity field. This is the correct default for
/// the existing LAN WebSocket path where the session token already provides
/// authentication and the local network is the trust boundary.
class PassthroughSyncFrameIntegrityChecker extends SyncFrameIntegrityChecker {
  const PassthroughSyncFrameIntegrityChecker();

  @override
  Map<String, dynamic> sign(Map<String, dynamic> frame) =>
      Map<String, dynamic>.from(frame);

  @override
  Map<String, dynamic>? verify(Map<String, dynamic> frame) =>
      Map<String, dynamic>.from(frame);
}

/// HMAC-SHA256 frame integrity checker.
///
/// For each data-plane eligible frame, [sign] computes
/// `HMAC-SHA256(secret, canonical(frame))` and adds it as
/// `_kash_sig` (hex-encoded). [verify] recomputes and constant-time
/// compares the proof before returning the cleaned frame.
///
/// Canonical form is a deterministic UTF-8 JSON string of the frame fields
/// *excluding* `_kash_sig`, keyed in lexicographic order. This matches the
/// convention already used by `P2pAuthService` for HTTP request signing.
class HmacSyncFrameIntegrityChecker extends SyncFrameIntegrityChecker {
  HmacSyncFrameIntegrityChecker({required List<int> secretBytes})
    : _secretBytes = List<int>.unmodifiable(secretBytes);

  static const _sigField = '_kash_sig';

  final List<int> _secretBytes;

  @override
  Map<String, dynamic> sign(Map<String, dynamic> frame) {
    final type = frame['type'];
    if (type is! String ||
        !SyncSignalingMessages.isDataPlaneEligibleType(type)) {
      return Map<String, dynamic>.from(frame);
    }

    final canonical = _canonicalize(frame);
    final sig = _computeHmac(canonical);

    return <String, dynamic>{
      ...Map<String, dynamic>.from(frame),
      _sigField: sig,
    };
  }

  @override
  Map<String, dynamic>? verify(Map<String, dynamic> frame) {
    final type = frame['type'];
    if (type is! String) return null;
    if (!SyncSignalingMessages.isDataPlaneEligibleType(type)) {
      return Map<String, dynamic>.from(frame);
    }

    final provided = frame[_sigField];
    if (provided is! String || provided.isEmpty) return null;

    // Strip the sig field before recomputing canonical form.
    final stripped = Map<String, dynamic>.from(frame)..remove(_sigField);
    final canonical = _canonicalize(stripped);
    final expected = _computeHmac(canonical);

    if (!_constantTimeEqual(expected, provided)) return null;

    return stripped;
  }

  /// Produces a deterministic canonical string by sorting keys lexicographically
  /// and JSON-encoding the resulting map.
  String _canonicalize(Map<String, dynamic> frame) {
    final sorted = Map<String, dynamic>.fromEntries(
      frame.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return jsonEncode(sorted);
  }

  String _computeHmac(String canonical) {
    final hmac = Hmac(sha256, _secretBytes);
    final digest = hmac.convert(utf8.encode(canonical));
    return digest.toString(); // hex string
  }

  /// Constant-time string comparison following the same pattern used in
  /// `P2pAuthService.verifyRequest` to prevent timing attacks.
  bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
