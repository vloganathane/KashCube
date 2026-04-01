// Stub for non-web platforms — returns empty params.
Map<String, String> getUrlParams() => {};

/// Token extracted from the browser URL on web platform start.
/// Always null on non-web platforms.
String? getInitialToken() => null;

/// Returns the http:// origin of the current page. Always null on non-web.
String? getOrigin() => null;

/// Returns full browser URL. Always null on non-web.
String? getCurrentUrl() => null;

// ── Session storage stubs (no-ops on native) ────────────────────────────────
void saveSession(String sessionId, String wsUrl) {}
String? getSavedSessionId() => null;
String? getSavedWsUrl() => null;
void clearSession() {}
