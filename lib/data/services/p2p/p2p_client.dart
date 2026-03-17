import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'p2p_auth_service.dart';

/// HTTP client for sending P2P sync requests to a peer's [P2pServer].
///
/// Every request is signed with HMAC-SHA256 (`X-Kash-Sig` + `X-Kash-Ts` +
/// `X-Kash-Id` headers). No SSL — requests travel only on the local LAN.
///
/// Usage:
/// ```dart
/// final client = P2pClient(
///   baseUrl:      'http://192.168.1.42:54321',
///   identityId:   myIdentityId,
///   sharedSecret: secret,
/// );
/// final ok = await client.hello();
/// final rows = await client.pull(table: 'invoices', afterVersion: 42);
/// await client.push(table: 'invoices', rows: [...]);
/// client.dispose();
/// ```
///
/// No network calls outside the local LAN — 100% privacy-first.
class P2pClient {
  P2pClient({
    required this.baseUrl,
    required this.identityId,
    required Uint8List sharedSecret,
  }) : _sharedSecret = sharedSecret;

  /// Base URL of the peer's HTTP server, e.g. `http://192.168.1.42:54321`.
  final String baseUrl;

  /// Our own identity ID, sent as `X-Kash-Id` so the server can look up the
  /// shared secret.
  final String identityId;

  final Uint8List _sharedSecret;

  final _httpClient = HttpClient()
    ..connectionTimeout  = const Duration(seconds: 5)
    ..idleTimeout        = const Duration(seconds: 10);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Checks that the peer is a KashCube node.
  /// Returns true if the handshake succeeds.
  Future<bool> hello() async {
    try {
      final resp = await _get('/hello');
      if (resp == null || resp.statusCode >= 400) return false;
      final body = await _readJson(resp);
      return body['app'] == 'kashcube';
    } catch (e) {
      debugPrint('[P2P] hello failed: $e');
      return false;
    }
  }

  /// Requests rows from [table] where version > [afterVersion].
  ///
  /// Returns the server's response map which contains a `rows` key
  /// (a `List<Map<String, dynamic>>`), or null on error.
  Future<Map<String, dynamic>?> pull({
    required String table,
    required int afterVersion,
  }) async {
    try {
      final resp = await _post(
        '/sync/pull',
        body: {'table': table, 'after_version': afterVersion},
      );
      if (resp == null || resp.statusCode >= 400) return null;
      return await _readJson(resp);
    } catch (e) {
      debugPrint('[P2P] pull($table) failed: $e');
      return null;
    }
  }

  /// Pushes [rows] for [table] to the peer.
  ///
  /// Returns true if the peer accepted the push.
  Future<bool> push({
    required String table,
    required List<Map<String, dynamic>> rows,
  }) async {
    try {
      final resp = await _post(
        '/sync/push',
        body: {'table': table, 'rows': rows},
      );
      if (resp == null || resp.statusCode >= 400) return false;
      final result = await _readJson(resp);
      return result['ok'] == true;
    } catch (e) {
      debugPrint('[P2P] push($table) failed: $e');
      return false;
    }
  }

  /// Frees the underlying [HttpClient].
  void dispose() => _httpClient.close(force: true);

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<HttpClientResponse?> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = await _httpClient.getUrl(uri);
    _attachAuthHeaders(request, 'GET', path, const []);
    return request.close();
  }

  Future<HttpClientResponse?> _post(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final bodyBytes = utf8.encode(jsonEncode(body));
    final uri       = Uri.parse('$baseUrl$path');
    final request   = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    _attachAuthHeaders(request, 'POST', path, bodyBytes);
    request.add(bodyBytes);
    return request.close();
  }

  void _attachAuthHeaders(
    HttpClientRequest request,
    String method,
    String path,
    List<int> body,
  ) {
    final ts = DateTime.now().toUtc().toIso8601String();
    final sig = P2pAuthService.instance.signRequest(
      method:       method,
      path:         path,
      timestamp:    ts,
      body:         body,
      sharedSecret: _sharedSecret,
    );
    request.headers
      ..set('x-kash-id',  identityId)
      ..set('x-kash-ts',  ts)
      ..set('x-kash-sig', sig);
  }

  Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
    final bytes = await response.expand((b) => b).toList();
    final str   = utf8.decode(bytes);
    return (jsonDecode(str) as Map<String, dynamic>?) ?? {};
  }
}
