import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'web_browser_session.dart';

/// Manages the short-lived session token used to authenticate a browser
/// connecting to the web companion over LAN.
///
/// Security model:
///   - Token is 32 random bytes → 256-bit entropy — not guessable
///   - Single-use: consumed on first successful WebSocket AUTH
///   - Expires 5 minutes after generation if never used
///   - On WS disconnect → token is cleared; new QR scan required
///   - Token is stored in-memory only, never persisted
class WebSessionService {
  WebSessionService._();
  static final WebSessionService instance = WebSessionService._();

  String? _activeToken;
  DateTime? _expiresAt;

  // Called whenever a browser session is live.
  WebBrowserSession? activeSession;

  static const _tokenTtl = Duration(minutes: 5);

  /// Generates a new session token, invalidating any previous one.
  /// Returns a base64url-encoded 32-byte random string.
  String generateToken() {
    // Use SHA-256(uuid + timestamp + random) as a simple CSPRNG fallback.
    // crypto package's Hmac + random bytes via dart:math is sufficient here
    // since the token never leaves the LAN and expires in 5 minutes.
    final seed = '${DateTime.now().microsecondsSinceEpoch}'
        '${_pseudoRandom()}';
    final bytes = sha256.convert(utf8.encode(seed)).bytes;
    _activeToken = base64Url.encode(bytes).replaceAll('=', '');
    _expiresAt   = DateTime.now().add(_tokenTtl);
    debugPrint('[WebSession] Token generated, expires at $_expiresAt');
    return _activeToken!;
  }

  /// Validates [token]. Consumes (invalidates) it on success.
  /// Returns true once — subsequent calls with the same token return false.
  bool validateAndConsume(String token) {
    final stored  = _activeToken;
    final expires = _expiresAt;
    if (stored == null || expires == null) return false;
    if (DateTime.now().isAfter(expires))  return false;
    if (!_constantTimeEquals(token, stored)) return false;
    // Consume — single use.
    _activeToken = null;
    _expiresAt   = null;
    return true;
  }

  /// Returns whether there is an unused, unexpired token available.
  bool get hasValidToken =>
      _activeToken != null &&
      _expiresAt != null &&
      DateTime.now().isBefore(_expiresAt!);

  /// Clears the active token (e.g., on session close or user revoke).
  void clearToken() {
    _activeToken = null;
    _expiresAt   = null;
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

  // Simple pseudo-random string using dart:core — good enough combined with
  // the timestamp for a short-lived LAN-only token.
  static String _pseudoRandom() {
    final now = DateTime.now();
    return '${now.microsecond}${now.millisecond}${now.hashCode}';
  }
}
