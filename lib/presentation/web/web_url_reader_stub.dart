// Stub for non-web platforms — returns empty params.
Map<String, String> getUrlParams() => {};

/// Token extracted from the browser URL on web platform start.
/// Always null on non-web platforms.
String? getInitialToken() => null;
