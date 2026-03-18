// Web implementation — reads token from the browser's current URL.
import 'package:web/web.dart' as web;

Map<String, String> getUrlParams() {
  try {
    final uri = Uri.parse(web.window.location.href);
    return uri.queryParameters;
  } catch (_) {
    return {};
  }
}

/// Returns the `token` parameter from the current browser URL, if present.
String? getInitialToken() => getUrlParams()['token'];
