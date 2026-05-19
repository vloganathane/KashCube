// Web implementation — reads token from the browser's current URL.
import 'package:web/web.dart' as web;

import '../../data/services/app_logger.dart';

const _kSessionId = 'kc_session_id';
const _kWsUrl = 'kc_ws_url';

Map<String, String> getUrlParams() {
  try {
    final uri = Uri.parse(web.window.location.href);
    return uri.queryParameters;
  } catch (e, st) {
    AppLogger.instance.warning(
      'Failed to parse URL parameters',
      category: 'web_url',
      error: e,
      stackTrace: st,
    );
    return {};
  }
}

/// Returns the `token` parameter from the current browser URL, if present.
String? getInitialToken() => getUrlParams()['token'];

/// Returns the http:// origin of the current page (scheme + host + port),
/// e.g. "http://192.168.1.8:8080".
String? getOrigin() {
  try {
    return web.window.location.origin;
  } catch (e, st) {
    AppLogger.instance.warning(
      'Failed to get window origin',
      category: 'web_url',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}

/// Returns full browser URL (href) on web, e.g.
/// http://192.168.1.6:50505/?token=...
String? getCurrentUrl() {
  try {
    return web.window.location.href;
  } catch (e, st) {
    AppLogger.instance.warning(
      'Failed to get current URL',
      category: 'web_url',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}

// ── Session token persistence (survives page refresh, cleared on tab close) ─

/// Saves [sessionId] and [wsUrl] to sessionStorage so a page refresh can
/// re-authenticate without requiring a new QR scan.
void saveSession(String sessionId, String wsUrl) {
  try {
    web.window.sessionStorage.setItem(_kSessionId, sessionId);
    web.window.sessionStorage.setItem(_kWsUrl, wsUrl);
  } catch (e) {
    AppLogger.instance.debug(
      'Failed to save session to sessionStorage',
      category: 'web_session',
      error: e,
    );
  }
}

/// Returns the stored session id, or null if not present.
String? getSavedSessionId() {
  try {
    final v = web.window.sessionStorage.getItem(_kSessionId);
    return (v == null || v.isEmpty) ? null : v;
  } catch (e) {
    AppLogger.instance.debug(
      'Failed to retrieve session ID from sessionStorage',
      category: 'web_session',
      error: e,
    );
    return null;
  }
}

/// Returns the stored WebSocket URL, or null if not present.
String? getSavedWsUrl() {
  try {
    final v = web.window.sessionStorage.getItem(_kWsUrl);
    return (v == null || v.isEmpty) ? null : v;
  } catch (e) {
    AppLogger.instance.debug(
      'Failed to retrieve WebSocket URL from sessionStorage',
      category: 'web_session',
      error: e,
    );
    return null;
  }
}

/// Clears the stored session (called on AUTH_FAIL or explicit disconnect).
void clearSession() {
  try {
    web.window.sessionStorage.removeItem(_kSessionId);
    web.window.sessionStorage.removeItem(_kWsUrl);
  } catch (e) {
    AppLogger.instance.debug(
      'Failed to clear session from sessionStorage',
      category: 'web_session',
      error: e,
    );
  }
}
