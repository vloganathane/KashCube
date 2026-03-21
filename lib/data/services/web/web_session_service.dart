import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'web_browser_session.dart';

/// Manages the short-lived session token used to authenticate a browser
/// connecting to the web companion over LAN.
///
/// Security model:
///   - QR token: 43-char base64url SHA-256; single-use; 5-minute TTL.
///   - Session token: issued after successful QR auth; multi-use; 30-minute TTL.
///     Stored by the browser in sessionStorage so page refreshes can
///     re-authenticate without requiring a new QR scan.
///   - All tokens are in-memory on the phone, never persisted to disk.
///   - On coordinator stop → both tokens cleared; new QR required.
class WebSessionService {
  WebSessionService._();
  static final WebSessionService instance = WebSessionService._();

  // ── QR token (single-use, 5 min) ─────────────────────────────────────────
  String? _activeToken;
  DateTime? _expiresAt;

  // ── Session token (multi-use, 30 min, reset on every reconnect) ──────────
  String? _sessionToken;
  DateTime? _sessionExpiry;

  // Called whenever a browser session is live.
  WebBrowserSession? activeSession;

  static const _tokenTtl   = Duration(minutes: 5);
  static const _sessionTtl = Duration(minutes: 30);

  static final Random _rng = Random.secure();

  /// Generates a new QR token, invalidating any previous one.
  /// Returns a 43-char base64url string of 32 cryptographically random bytes.
  String generateToken() {
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    _activeToken = base64Url.encode(bytes).replaceAll('=', '');
    _expiresAt   = DateTime.now().add(_tokenTtl);
    debugPrint('[WebSession] QR token generated, expires at $_expiresAt');
    return _activeToken!;
  }

  /// Validates the QR [token]. Consumes (invalidates) it on success so it
  /// cannot be reused for a second browser. On success also generates a
  /// fresh session token valid for 30 minutes (returned via [sessionToken]).
  bool validateAndConsume(String token) {
    final stored  = _activeToken;
    final expires = _expiresAt;
    if (stored == null || expires == null) return false;
    if (DateTime.now().isAfter(expires))  return false;
    if (!_constantTimeEquals(token, stored)) return false;
    // Consume QR token — single use.
    _activeToken = null;
    _expiresAt   = null;
    // Issue a session token for refresh re-auth.
    _issueSessionToken();
    return true;
  }

  /// Validates a session token (used on page refresh when the QR token is gone).
  /// Re-extends the TTL on each successful validation (rolling window).
  bool validateSession(String token) {
    final stored  = _sessionToken;
    final expires = _sessionExpiry;
    if (stored == null || expires == null) return false;
    if (DateTime.now().isAfter(expires))  return false;
    if (!_constantTimeEquals(token, stored)) return false;
    // Roll the 30-minute window forward.
    _sessionExpiry = DateTime.now().add(_sessionTtl);
    return true;
  }

  /// The current session token to include in AUTH_OK — null before first auth.
  String? get sessionToken => _sessionToken;

  /// Returns whether there is an unused, unexpired QR token available.
  bool get hasValidToken =>
      _activeToken != null &&
      _expiresAt != null &&
      DateTime.now().isBefore(_expiresAt!);

  /// Clears both tokens (e.g., on coordinator stop or user revoke).
  void clearToken() {
    _activeToken   = null;
    _expiresAt     = null;
    _sessionToken  = null;
    _sessionExpiry = null;
  }

  void _issueSessionToken() {
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    _sessionToken  = base64Url.encode(bytes).replaceAll('=', '');
    _sessionExpiry = DateTime.now().add(_sessionTtl);
    debugPrint('[WebSession] Session token issued, expires at $_sessionExpiry');
  }

  // Constant-time string comparison to avoid timing attacks.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

}
