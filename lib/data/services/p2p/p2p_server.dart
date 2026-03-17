import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'p2p_auth_service.dart';

/// Lightweight HTTP server for P2P LAN sync.
///
/// Lifecycle:
///   1. Call [start] from the P2P coordinator — it binds to a random OS port.
///   2. Pass [port] to [P2pDiscoveryService.startBroadcast].
///   3. Call [stop] when sync is disabled or the app goes to background.
///
/// Security:
///   - Every non-hello route is protected by HMAC-SHA256 middleware.
///   - The shared secret for each peer is looked up by `X-Kash-Id` header.
///   - Replayed requests are rejected via 30-second clock skew window.
///
/// No network calls — all traffic is LAN-only.
class P2pServer {
  P2pServer._();
  static final P2pServer instance = P2pServer._();

  HttpServer? _server;

  /// Port the server is currently bound to, or null if not running.
  int? get port => _server?.port;

  // Injected at [start] time by the coordinator.
  Future<Uint8List?> Function(String identityId)? _secretForPeer;
  Future<Map<String, dynamic>> Function(String table, int afterVersion)?
      _pullHandler;
  Future<void> Function(String table, List<Map<String, dynamic>> rows)?
      _pushHandler;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the HTTP server on a random OS-assigned port.
  ///
  /// [secretForPeer]   Async callback: given a peer's identityId, returns the
  ///                   32-byte shared secret (or null if the peer is unknown).
  /// [onPull]          Callback that returns rows for [table] with version >
  ///                   [afterVersion].
  /// [onPush]          Callback that persists incoming [rows] for [table].
  Future<void> start({
    required Future<Uint8List?> Function(String identityId) secretForPeer,
    required Future<Map<String, dynamic>> Function(
            String table, int afterVersion)
        onPull,
    required Future<void> Function(
            String table, List<Map<String, dynamic>> rows)
        onPush,
  }) async {
    if (_server != null) return;

    _secretForPeer = secretForPeer;
    _pullHandler   = onPull;
    _pushHandler   = onPush;

    final router = _buildRouter();

    final handler = const Pipeline()
        .addMiddleware(_hmacMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      0, // OS assigns a random free port
      shared: false,
    );
    debugPrint('[P2P] Server listening on port ${_server!.port}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    debugPrint('[P2P] Server stopped');
  }

  // ── Routes ────────────────────────────────────────────────────────────────

  Router _buildRouter() {
    final router = Router();

    /// Handshake — no auth required. Returns a JSON object so the caller can
    /// verify this is a KashCube node before attempting to pair.
    router.get('/hello', _helloHandler);

    /// Pull: requester asks for all rows in [table] after [afterVersion].
    router.post('/sync/pull', _pullHandlerRoute);

    /// Push: requester sends rows for [table] that the server should merge.
    router.post('/sync/push', _pushHandlerRoute);

    return router;
  }

  Response _helloHandler(Request request) {
    return Response.ok(
      jsonEncode({'app': 'kashcube', 'proto': 1}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _pullHandlerRoute(Request request) async {
    final body = await _readBody(request);
    final table       = body['table'] as String?;
    final afterVersion = body['after_version'] as int?;

    if (table == null || afterVersion == null) {
      return Response(400, body: jsonEncode({'error': 'missing params'}));
    }

    final result = await _pullHandler!(table, afterVersion);
    return Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _pushHandlerRoute(Request request) async {
    final body  = await _readBody(request);
    final table = body['table'] as String?;
    final rows  = (body['rows'] as List?)?.cast<Map<String, dynamic>>();

    if (table == null || rows == null) {
      return Response(400, body: jsonEncode({'error': 'missing params'}));
    }

    await _pushHandler!(table, rows);
    return Response.ok(jsonEncode({'ok': true}));
  }

  // ── HMAC middleware ───────────────────────────────────────────────────────

  /// Rejects requests that are missing or have invalid HMAC signatures.
  /// The /hello route is exempt (no shared secret needed for discovery).
  Middleware _hmacMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        if (request.url.path == 'hello') return inner(request);

        final identityId = request.headers['x-kash-id'];
        final signature  = request.headers['x-kash-sig'];
        final timestamp  = request.headers['x-kash-ts'];

        if (identityId == null || signature == null || timestamp == null) {
          return Response(401, body: jsonEncode({'error': 'missing auth headers'}));
        }

        final secret = await _secretForPeer!(identityId);
        if (secret == null) {
          return Response(403, body: jsonEncode({'error': 'unknown peer'}));
        }

        // Buffer the body so we can both verify and forward it.
        final bodyBytes = await request.read().expand((b) => b).toList();

        final valid = P2pAuthService.instance.verifyRequest(
          method:       request.method,
          path:         '/${request.url.path}',
          receivedTs:   timestamp,
          body:         bodyBytes,
          sharedSecret: secret,
          receivedSig:  signature,
        );

        if (!valid) {
          return Response(401, body: jsonEncode({'error': 'invalid signature'}));
        }

        // Re-attach the buffered body for downstream handlers.
        final updated = request.change(body: bodyBytes);
        return inner(updated);
      };
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _readBody(Request request) async {
    final raw = await request.readAsString();
    if (raw.isEmpty) return {};
    return (jsonDecode(raw) as Map<String, dynamic>?) ?? {};
  }
}
