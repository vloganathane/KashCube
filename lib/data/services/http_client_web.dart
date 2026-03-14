import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Posts a JSON body to [url] with the session token header.
/// Returns the decoded JSON response body.
/// Throws a descriptive [String] on network / timeout / server errors.
Future<Map<String, dynamic>> httpPost(
  String url,
  Map<String, dynamic> body, {
  required String sessionToken,
}) {
  final completer = Completer<Map<String, dynamic>>();
  final xhr = web.XMLHttpRequest();

  xhr.open('POST', url, true);
  xhr.setRequestHeader('Content-Type', 'application/json');
  xhr.setRequestHeader('X-KashCube-Token', sessionToken);
  xhr.timeout = 8000; // ms — fail fast on AP-isolated networks

  xhr.onload = (web.Event _) {
    if (completer.isCompleted) return;
    if (xhr.status >= 200 && xhr.status < 300) {
      try {
        final decoded = jsonDecode(xhr.responseText) as Map<String, dynamic>;
        completer.complete(decoded);
      } catch (e) {
        completer.completeError('Bad JSON from server: $e');
      }
    } else {
      completer.completeError(
          'Server returned ${xhr.status}: ${xhr.responseText}');
    }
  }.toJS;

  xhr.onerror = (web.Event _) {
    if (completer.isCompleted) return;
    completer.completeError(
      'Connection failed. Make sure your phone and browser are on the same '
      'network. If your router has AP isolation, use your phone\'s Mobile '
      'Hotspot instead.',
    );
  }.toJS;

  xhr.ontimeout = (web.Event _) {
    if (completer.isCompleted) return;
    completer.completeError(
      'Connection timed out. The phone may be unreachable — check that both '
      'devices are on the same Wi-Fi and the KashCube server is running.',
    );
  }.toJS;

  xhr.send(jsonEncode(body).toJS);
  return completer.future;
}
