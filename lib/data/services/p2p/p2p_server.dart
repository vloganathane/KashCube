import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../web/web_browser_session.dart';
import '../web/web_session_service.dart';
import '../web/web_ui_extractor.dart';
import '../../../core/constants/app_constants.dart';
import 'p2p_auth_service.dart';

/// Lightweight HTTP server for P2P LAN sync.
///
/// Lifecycle:
///   1. Call [start] from the P2P coordinator — it prefers [AppConstants.p2pPort]
///      and falls back to a random OS-assigned port if the preferred one is busy.
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
  bool _staticReady = false;

  /// Port the server is currently bound to, or null if not running.
  int? get port => _server?.port;

  /// True when the server socket is bound and static web UI is pre-warmed.
  Future<bool> isHealthy() async {
    return _server != null && _staticReady;
  }

  // Injected at [start] time by the coordinator.
  Future<Uint8List?> Function(String identityId)? _secretForPeer;
  Future<Map<String, dynamic>> Function(String table, int afterVersion)?
      _pullHandler;
  Future<void> Function(String table, List<Map<String, dynamic>> rows)?
      _pushHandler;
  Future<bool> Function(String identityId, String publicKeyBase64,
      String displayName, String proof)? _pairHandler;

  // ── Web companion ─────────────────────────────────────────────────────────

  String? _webDeviceName;
  int?    _webSchemaVersion;
  Future<void> Function(String table, Map<String, dynamic> row)? _webOnWrite;
  WebBrowserSession? _activeSession;

  /// Call this (after [start]) to enable the browser web companion routes.
  ///
  /// [deviceName]    — phone's display name shown in the browser AUTH_OK.
  /// [schemaVersion] — current DB schema version (for client compatibility).
  /// [onWrite]       — called when the browser submits a WRITE message.
  void enableWebCompanion({
    required String deviceName,
    required int    schemaVersion,
    required Future<void> Function(String table, Map<String, dynamic> row) onWrite,
  }) {
    _webDeviceName    = deviceName;
    _webSchemaVersion = schemaVersion;
    _webOnWrite       = onWrite;
    debugPrint('[P2P] Web companion enabled for $deviceName');
  }

  /// Disconnects the active browser session (e.g., user taps "Disconnect browser").
  void disconnectBrowser() {
    _activeSession?.dispose();
    _activeSession = null;
    WebSessionService.instance.clearToken();
  }

  bool get hasBrowserConnected => _activeSession != null;

  // ── Browser connection events ─────────────────────────────────────────────

  /// Emits `true` when a browser authenticates (AUTH_OK sent).
  /// Consumers can use this to trigger analytics or UI updates.
  final _browserConnectionController = StreamController<bool>.broadcast();
  Stream<bool> get browserConnectionStream => _browserConnectionController.stream;

  // ── HTTP request log ──────────────────────────────────────────────────────

  static const _kMaxLogEntries = 60;
  final _httpLogEntries = <String>[];
  final _httpLogController = StreamController<List<String>>.broadcast();

  /// Live stream of HTTP request/response entries for the diagnostics panel.
  Stream<List<String>> get httpLogStream => _httpLogController.stream;

  /// Current snapshot of the HTTP log (newest at end).
  List<String> get currentHttpLog => List.unmodifiable(_httpLogEntries);

  /// Clears all captured HTTP request log entries and notifies listeners.
  void clearHttpLog() {
    _httpLogEntries.clear();
    if (!_httpLogController.isClosed) {
      _httpLogController.add(List.unmodifiable(_httpLogEntries));
    }
  }

  void _addHttpLog(String message) {
    final n  = DateTime.now();
    final ts = '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
    final entry = '$ts  $message';
    _httpLogEntries.add(entry);
    if (_httpLogEntries.length > _kMaxLogEntries) _httpLogEntries.removeAt(0);
    if (!_httpLogController.isClosed) {
      _httpLogController.add(List.unmodifiable(_httpLogEntries));
    }
    debugPrint('[P2P-http] $message');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the HTTP server.
  ///
  /// Binding strategy:
  ///   1) Try [AppConstants.p2pPort] first (predictable/manual URL friendly)
  ///   2) If unavailable, retry with port `0` (OS-assigned random free port)
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
    required Future<bool> Function(String identityId, String publicKeyBase64,
            String displayName, String proof)
        onPairRequest,
  }) async {
    if (_server != null) return;

    _secretForPeer = secretForPeer;
    _pullHandler   = onPull;
    _pushHandler   = onPush;
    _pairHandler   = onPairRequest;

    // ── Route groups ──────────────────────────────────────────────────────
    //
    // Traffic is handled in cascade order:
    //   1. Unauthenticated routes: /hello, /pair, /ws (WebSocket)
    //   2. HMAC-authenticated P2P sync routes: /sync/*
    //   3. Static web UI file serving: GET /*
    //
    // The HMAC middleware is only applied to layer 2 — WebSocket and static
    // serving bypass it entirely.

    // Layer 1 — open routes (no HMAC)
    final openRouter = Router()
      ..get('/hello', _helloHandler)
      ..get('/health', _healthHandler)
      ..post('/pair', _pairHandlerRoute)
      ..get('/ws',    _wsHandler());

    // Layer 2 — HMAC-gated P2P sync routes
    final syncRouter = Router()
      ..post('/sync/pull', _pullHandlerRoute)
      ..post('/sync/push', _pushHandlerRoute);

    final syncHandler = const Pipeline()
        .addMiddleware(_hmacMiddleware())
        .addHandler(syncRouter.call);

    // Pre-warm web UI extraction before serving requests so the first browser
    // hit does not pay extraction latency (or see transient 500s).
    await WebUiExtractor.instance.extractNow();

    // Layer 3 — static web UI (pre-extracted from assets/web_ui/)
    final staticHandler = _buildStaticHandler();

    // Combined cascade
    final combined = Cascade()
        .add(openRouter.call)
        .add(syncHandler)
        .add(staticHandler)
        .handler;

    // Thin request-log middleware — logs every inbound request with the
    // remote address so connectivity issues on other devices can be diagnosed.
    final logged = const Pipeline()
        .addMiddleware(_requestLogMiddleware())
        .addHandler(combined);

    try {
      _server = await shelf_io.serve(
        logged,
        InternetAddress.anyIPv4,
        AppConstants.p2pPort,
        shared: false,
        poweredByHeader: 'KashCube',
      );
      _addHttpLog('PORT bind ${AppConstants.p2pPort} (preferred)');
    } on SocketException catch (e) {
      debugPrint(
        '[P2P] Preferred port ${AppConstants.p2pPort} unavailable: $e. Retrying with random port.',
      );
      _server = await shelf_io.serve(
        logged,
        InternetAddress.anyIPv4,
        0,
        shared: false,
        poweredByHeader: 'KashCube',
      );
      _addHttpLog(
        'PORT fallback ${AppConstants.p2pPort} -> ${_server!.port}',
      );
    }
    _staticReady = true;
    debugPrint('[P2P] Server listening on 0.0.0.0:${_server!.port}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _staticReady = false;
    clearHttpLog();
    debugPrint('[P2P] Server stopped');
  }

  // ── Route handlers ────────────────────────────────────────────────────────

  /// WebSocket upgrade handler for `/ws`.
  /// Browser sends AUTH message with session token; token validated via
  /// [WebSessionService]. No HMAC required — token possession = auth.
  Handler _wsHandler() => webSocketHandler(
        (WebSocketChannel channel, String? _) {
          if (_webDeviceName == null || _webSchemaVersion == null) {
            _addHttpLog('WS  /ws  REJECTED (web companion not enabled)');
            channel.sink.close();
            return;
          }
          // Dispose any existing session (one browser at a time).
          _activeSession?.dispose();
          _addHttpLog('WS  /ws  CONNECTED');
          final session = WebBrowserSession(
            channel:         channel,
            validateToken:   WebSessionService.instance.validateAndConsume,
            validateSession: WebSessionService.instance.validateSession,
            getSessionToken: () => WebSessionService.instance.sessionToken,
            onWrite:         _webOnWrite ?? (_, p2) async {},
            schemaVersion:   _webSchemaVersion!,
            deviceName:      _webDeviceName!,
            onAuthenticated: (_) {
              if (!_browserConnectionController.isClosed) {
                _browserConnectionController.add(true);
              }
            },
            onDisposed: () {
              _activeSession = null;
              if (!_browserConnectionController.isClosed) {
                _browserConnectionController.add(false);
              }
            },
          );
          _activeSession = session;
          session.attach();
          WebSessionService.instance.activeSession = session;
        },
        allowedOrigins: null, // allow all origins — server is local-only
      );

  /// Returns a shelf handler that lazily extracts `assets/web_ui/` to a temp
  /// directory and serves it with `shelf_static`.
  ///
  /// CORS header is added so same-origin WebSocket handshake works correctly
  /// even on strict browser security policies.
  Handler _buildStaticHandler() {
    Handler? cached;
    return (Request request) async {
      if (cached == null) {
        try {
          final path = await WebUiExtractor.instance.getExtractedPath();
          cached = createStaticHandler(
            path,
            defaultDocument: 'index.html',
            serveFilesOutsidePath: false,
          );
        } catch (e) {
          debugPrint('[P2P] Static handler init error: $e');
          return Response.internalServerError(
            body: 'Web UI not available: $e',
          );
        }
      }
      final response = await cached!(request);
      // Add CORS for the static web UI (browser same-origin allows /ws).
      return response.change(headers: {
        ...response.headers,
        'Access-Control-Allow-Origin': '*',
      });
    };
  }

  Response _helloHandler(Request request) {
    return Response.ok(
      jsonEncode({'app': 'kashcube', 'proto': 1}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _healthHandler(Request request) {
    final healthy = _server != null && _staticReady;
    final payload = jsonEncode({
      'status': healthy ? 'healthy' : 'warming_up',
      'server_bound': _server != null,
      'static_ready': _staticReady,
      'port': _server?.port,
    });
    return Response(
      healthy ? 200 : 503,
      body: payload,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _pairHandlerRoute(Request request) async {
    final body        = await _readBody(request);
    final identityId  = body['identity_id']  as String?;
    final publicKey   = body['public_key']   as String?;
    final displayName = body['display_name'] as String? ?? 'Unknown Device';
    final proof       = body['proof']        as String?;

    if (identityId == null || publicKey == null || proof == null) {
      return Response(400, body: jsonEncode({'error': 'missing fields'}));
    }

    final accepted = await _pairHandler!(identityId, publicKey, displayName, proof);
    if (!accepted) {
      return Response(403, body: jsonEncode({'error': 'invalid proof'}));
    }
    return Response.ok(
      jsonEncode({'ok': true}),
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

  // ── Request-log middleware ────────────────────────────────────────────────

  /// Logs every inbound request (method, path, remote IP) so connectivity
  /// problems from other devices on the LAN can be diagnosed quickly.
  Middleware _requestLogMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final info = request.context['shelf.io.connection_info'];
        final remoteAddr = info is HttpConnectionInfo
            ? info.remoteAddress.address
            : '?';
        final response = await inner(request);
        _addHttpLog(
          '${response.statusCode}  ${request.method.padRight(4)}  '
          '/${request.url.path}  from=$remoteAddr',
        );
        return response;
      };
    };
  }

  // ── HMAC middleware ───────────────────────────────────────────────────────
  /// Only applied to the sync router — open and static routes bypass it.
  Middleware _hmacMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        // Only enforce HMAC for /sync/* — let everything else fall through so
        // that Cascade can continue to the static web-UI handler.
        final path = '/${request.url.path}';
        if (!path.startsWith('/sync/')) {
          return inner(request);
        }

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
