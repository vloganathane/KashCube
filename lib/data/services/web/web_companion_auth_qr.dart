/// Browser-initiated QR handshake payload for the web companion.
///
/// Protocol v1:
///   1. Browser opens plain `http://<phone-ip>:<port>`
///   2. Browser WebSocket sends AUTH_BEGIN
///   3. Phone server returns AUTH_CHALLENGE with a single-use QR payload
///   4. User scans that QR using KashCube on the phone
///   5. Phone approves the pending browser session in-process
///   6. Browser receives AUTH_OK with a rolling session token
///
/// QR format:
///   `kashcube://web-auth?v=1&sid=<browser_session_id>&ch=<challenge>`
String buildWebCompanionAuthQr({
  required String sessionId,
  required String challenge,
}) {
  return Uri(
    scheme: 'kashcube',
    host: 'web-auth',
    queryParameters: {
      'v': '1',
      'sid': sessionId,
      'ch': challenge,
    },
  ).toString();
}

({String sessionId, String challenge})? parseWebCompanionAuthQr(String raw) {
  try {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme != 'kashcube' || uri.host != 'web-auth') {
      return null;
    }
    if (uri.queryParameters['v'] != '1') {
      return null;
    }
    final sessionId = uri.queryParameters['sid'];
    final challenge = uri.queryParameters['ch'];
    if (sessionId == null || sessionId.isEmpty) return null;
    if (challenge == null || challenge.isEmpty) return null;
    return (sessionId: sessionId, challenge: challenge);
  } catch (_) {
    return null;
  }
}
