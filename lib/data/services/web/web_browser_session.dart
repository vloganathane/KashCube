import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_logger.dart';
import 'web_companion_auth_qr.dart';
import '../database_helper.dart';
import '../sync/generic_sync_query_builder.dart';
import '../sync/transport/sync_signaling_messages.dart';
import '../sync/sync_table_registry.dart';
import 'web_session_service.dart';

typedef WebSignalFrameHandler = Future<List<Map<String, dynamic>>> Function(
  Map<String, dynamic> frame,
);

/// Manages a single browser's WebSocket session.
///
/// Lifecycle:
///   1. [P2pServer] upgrades the `/ws` connection → creates this session.
///   2. Browser sends `{"type":"AUTH","token":"..."}` → [_authenticate].
///   3. Browser pulls tables via `{"type":"PULL","table":"...","since":"..."}`.
///   4. Phone pushes live updates to browser via [pushRows].
///   5. Browser writes via `{"type":"WRITE","table":"...","row":{...}}`.
///   6. On disconnect → [dispose] is called.
class WebBrowserSession {
  WebBrowserSession({
    required this.channel,
    required this.validateToken,
    required this.validateSession,
    required this.getSessionToken,
    required this.onWrite,
    this.onSignalFrame,
    required this.schemaVersion,
    required this.deviceName,
    this.onAuthenticated,
    this.onDisposed,
  });

  final WebSocketChannel channel;

  /// Validates and consumes the QR token — returns true if accepted.
  final bool Function(String token) validateToken;

  /// Validates a session token issued after QR auth (for page refresh re-auth).
  final bool Function(String token) validateSession;

  /// Returns the current session token to embed in AUTH_OK.
  final String? Function() getSessionToken;

  /// Called when browser writes a row — phone persists it.
  final Future<void> Function(String table, Map<String, dynamic> row) onWrite;

  /// Optional handler for WebRTC signaling frames from browser.
  ///
  /// If set, SIGNAL_* frames are delegated to this callback and each returned
  /// frame is sent back to the browser. If unset, the session responds with
  /// SIGNAL_UNSUPPORTED.
  final WebSignalFrameHandler? onSignalFrame;

  /// Optional callback fired after the browser successfully authenticates.
  /// [isSession] is true when re-auth used a session token (page refresh).
  final void Function(bool isSession)? onAuthenticated;

  /// Optional callback fired when this session is disposed (WS closed or
  /// explicit disconnect).  Used by [P2pServer] to clear its session reference
  /// and emit a disconnect event to [WebCompanionService].
  final VoidCallback? onDisposed;

  final int schemaVersion;
  final String deviceName;

  bool _authenticated = false;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  final Map<String, SyncTablePlan> _syncPlans = {};
  String? _pendingBrowserSessionId;
  String? _pendingChallenge;
  DateTime? _pendingExpiresAt;
  DateTime? _attachedAt;
  DateTime? _challengeIssuedAt;

  static const _pingInterval = Duration(seconds: 25);
  static const _pendingAuthTtl = Duration(minutes: 5);
  static final Random _rng = Random.secure();
  Timer? _pingTimer;
  Timer? _authTimer;

  void attach() {
    _attachedAt = DateTime.now();
    unawaited(AppLogger.instance.info(
      'Web companion timing trace',
      category: 'web_companion_timing',
      eventName: 'web_companion_timing',
      context: {
        'stage': 'ws_attached',
      },
    ));

    _sub = channel.stream.listen(
      _onMessage,
      onDone:  dispose,
      onError: (_) => dispose(),
    );
    // Give the browser 10 seconds to authenticate.
    Future<void>.delayed(const Duration(seconds: 10), () {
      if (!_authenticated && !_disposed && _pendingBrowserSessionId == null) {
        _sendRaw({'type': 'AUTH_FAIL', 'reason': 'timeout'});
        dispose();
      }
    });
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final msg  = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = (msg['type'] as String? ?? '').toUpperCase();
      switch (type) {
        case SyncSignalingMessages.auth:
        case SyncSignalingMessages.sessionAuth:
          _handleAuth(msg, isSession: type == SyncSignalingMessages.sessionAuth);
          break;
        case SyncSignalingMessages.authBegin:
          _handleAuthBegin();
          break;
        case SyncSignalingMessages.pull:
          _handlePull(msg);
          break;
        case SyncSignalingMessages.write:
          _handleWrite(msg);
          break;
        case SyncSignalingMessages.ping:
          _sendRaw({'type': SyncSignalingMessages.pong});
          break;
        case SyncSignalingMessages.pong:
          // Browser keepalive acknowledgment for server-initiated ping.
          break;
        case SyncSignalingMessages.signalOffer:
        case SyncSignalingMessages.signalAnswer:
        case SyncSignalingMessages.signalIceCandidate:
          unawaited(_handleSignalFrame(type, msg));
          break;
        default:
          debugPrint('[WebSession] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[WebSession] Message parse error: $e');
    }
  }

  void _handleAuth(Map<String, dynamic> msg, {bool isSession = false}) {
    final token = msg['token'] as String?;
    final valid = token != null &&
        (isSession ? validateSession(token) : validateToken(token));
    if (!valid) {
      _sendRaw({'type': 'AUTH_FAIL', 'reason': 'invalid_token'});
      dispose();
      return;
    }
    _pendingBrowserSessionId = null;
    _pendingChallenge = null;
    _pendingExpiresAt = null;
    _authTimer?.cancel();
    _completeAuthentication(
      sessionId: getSessionToken(),
      isSession: isSession,
    );
  }

  void _handleAuthBegin() {
    if (_authenticated || _disposed) return;

    final sessionId = _randomToken(16);
    final challenge = _randomToken(32);
    final expiresAt = DateTime.now().add(_pendingAuthTtl);
    _pendingBrowserSessionId = sessionId;
    _pendingChallenge = challenge;
    _pendingExpiresAt = expiresAt;
    _challengeIssuedAt = DateTime.now();

    _authTimer?.cancel();
    _authTimer = Timer(_pendingAuthTtl, () {
      if (!_authenticated && !_disposed) {
        _sendRaw({'type': 'AUTH_FAIL', 'reason': 'approval_timeout'});
        dispose();
      }
    });

    _sendRaw({
      'type': 'AUTH_CHALLENGE',
      'browser_session_id': sessionId,
      'expires_at': expiresAt.toIso8601String(),
      'qr_payload': buildWebCompanionAuthQr(
        sessionId: sessionId,
        challenge: challenge,
      ),
    });
    final wsToChallengeMs = _attachedAt == null
        ? null
        : _challengeIssuedAt!.difference(_attachedAt!).inMilliseconds;
    unawaited(AppLogger.instance.info(
      'Web companion timing trace',
      category: 'web_companion_timing',
      eventName: 'web_companion_timing',
      context: {
        'stage': 'auth_challenge_issued',
        'ws_to_challenge_ms': wsToChallengeMs,
      },
    ));
    debugPrint('[WebSession] Browser auth challenge issued, expires at $expiresAt');
  }

  bool approvePendingAuth(String sessionId, String challenge) {
    if (_disposed || _authenticated) return false;
    if (_pendingBrowserSessionId == null || _pendingChallenge == null) {
      return false;
    }
    final expiresAt = _pendingExpiresAt;
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      return false;
    }
    if (!_constantTimeEquals(sessionId, _pendingBrowserSessionId!)) {
      return false;
    }
    if (!_constantTimeEquals(challenge, _pendingChallenge!)) {
      return false;
    }

    _pendingBrowserSessionId = null;
    _pendingChallenge = null;
    _pendingExpiresAt = null;
    _authTimer?.cancel();
    final approvedAt = DateTime.now();
    final challengeToApproveMs = _challengeIssuedAt == null
        ? null
        : approvedAt.difference(_challengeIssuedAt!).inMilliseconds;
    unawaited(AppLogger.instance.info(
      'Web companion timing trace',
      category: 'web_companion_timing',
      eventName: 'web_companion_timing',
      context: {
        'stage': 'phone_approval_received',
        'challenge_to_approve_ms': challengeToApproveMs,
      },
    ));

    final issuedSessionId = WebSessionService.instance.issueSessionToken();
    _completeAuthentication(
      sessionId: issuedSessionId,
      isSession: false,
    );
    return true;
  }

  void _completeAuthentication({
    required String? sessionId,
    required bool isSession,
  }) {
    final now = DateTime.now();
    final wsToAuthOkMs = _attachedAt == null
        ? null
        : now.difference(_attachedAt!).inMilliseconds;
    final challengeToAuthOkMs = _challengeIssuedAt == null
        ? null
        : now.difference(_challengeIssuedAt!).inMilliseconds;

    _authenticated = true;
    _sendRaw({
      'type':           SyncSignalingMessages.authOk,
      'device_name':    deviceName,
      'schema_version': schemaVersion,
      'session_id': ?sessionId,
    });
    unawaited(AppLogger.instance.info(
      'Web companion timing trace',
      category: 'web_companion_timing',
      eventName: 'web_companion_timing',
      context: {
        'stage': 'auth_ok_sent',
        'auth_mode': isSession ? 'session' : 'qr',
        'ws_to_auth_ok_ms': wsToAuthOkMs,
        'challenge_to_auth_ok_ms': challengeToAuthOkMs,
      },
    ));
    onAuthenticated?.call(isSession);
    _startPing();
    unawaited(_sendSyncPlan());
    debugPrint('[WebSession] Browser authenticated (${isSession ? 'session' : 'QR'})');
  }

  Future<void> _sendSyncPlan() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await _ensureSyncPlans(db);
      final tables = _syncPlans.values
          .where((p) => p.isWebEligible)
          .map((p) => {
                'name': p.tableName,
                'mode': p.mode.name,
                'key':  p.keyColumn,
              })
          .toList();
        _sendRaw({'type': SyncSignalingMessages.syncPlan, 'tables': tables});
    } catch (e) {
      debugPrint('[WebSession] Failed to send sync plan: $e');
    }
  }

  Future<void> _handlePull(Map<String, dynamic> msg) async {
    if (!_authenticated) return;
    final table = msg['table'] as String?;
    final since = msg['since'] as String?;
    if (table == null) return;

    try {
      final db  = await DatabaseHelper.instance.database;
      final rows = await _queryRows(db, table, since);

      // Send in batches of 200 to avoid huge single frames.
      const batchSize = 200;
      for (var i = 0; i < rows.length || rows.isEmpty; i += batchSize) {
        final batch    = rows.isEmpty ? <Map<String, dynamic>>[] : rows.sublist(
          i,
          (i + batchSize).clamp(0, rows.length),
        );
        final isFinal = rows.isEmpty || (i + batchSize >= rows.length);
        _sendRaw({
          'type':     SyncSignalingMessages.rows,
          'table':    table,
          'rows':     batch,
          'is_final': isFinal,
        });
        if (isFinal) break;
      }
    } catch (e) {
      debugPrint('[WebSession] Pull error for $table: $e');
    }
  }

  Future<void> _handleWrite(Map<String, dynamic> msg) async {
    if (!_authenticated) return;
    final table  = msg['table'] as String?;
    final row    = msg['row']   as Map<String, dynamic>?;
    final syncId = msg['sync_id'] as String?;
    if (table == null || row == null) return;

    // Reject writes to phone-only or local-only tables.
    final plan = _syncPlans[table];
    if (plan != null && !plan.isWebEligible) {
      debugPrint('[WebSession] Write rejected for phone-only table: $table');
      return;
    }

    try {
      await onWrite(table, row);
      _sendRaw({'type': SyncSignalingMessages.writeOk, 'sync_id': syncId});
      // Echo back as PUSH so browser has the canonical row.
      _sendRaw({'type': SyncSignalingMessages.push, 'table': table, 'rows': [row]});
    } catch (e) {
      debugPrint('[WebSession] Write error for $table: $e');
    }
  }

  Future<void> _handleSignalFrame(
    String type,
    Map<String, dynamic> msg,
  ) async {
    if (!_authenticated) return;

    final handler = onSignalFrame;
    if (handler == null) {
      _sendRaw({
        'type': SyncSignalingMessages.signalUnsupported,
        'reason': 'WebRTC signaling handler not configured',
        'source_type': type,
      });
      return;
    }

    final frame = Map<String, dynamic>.from(msg)
      ..['type'] = type;

    try {
      final responses = await handler(frame);
      for (final response in responses) {
        _sendRaw(response);
      }
    } catch (e) {
      debugPrint('[WebSession] Signal frame error ($type): $e');
      _sendRaw({
        'type': SyncSignalingMessages.signalUnsupported,
        'reason': 'WebRTC signaling handler error',
        'source_type': type,
      });
    }
  }

  /// Pushes a live update to the browser (called when phone writes a row).
  void pushRows(String table, List<Map<String, dynamic>> rows) {
    if (!_authenticated || _disposed) return;
    _sendRaw({'type': SyncSignalingMessages.push, 'table': table, 'rows': rows});
  }

  void _sendRaw(Map<String, dynamic> payload) {
    if (_disposed) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[WebSession] Send error: $e');
    }
  }

  void _startPing() {
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (!_disposed) _sendRaw({'type': SyncSignalingMessages.ping});
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _authTimer?.cancel();
    _pingTimer?.cancel();
    _sub?.cancel();
    try {
      channel.sink.close();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Web session close failed',
        category: 'web_session',
        error: e,
        stackTrace: st,
      );
    }
    onDisposed?.call();
    debugPrint('[WebSession] Browser session ended');
  }

  static String _randomToken(int byteLength) {
    final bytes = List<int>.generate(byteLength, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  // ── DB helper ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _queryRows(
    Database db,
    String table,
    String? since,
  ) async {
    await _ensureSyncPlans(db);
    final plan = _syncPlans[table];
    if (plan == null || !plan.isWebEligible) {
      debugPrint('[WebSession] Pull rejected for table: $table (scope=${plan?.scope.name ?? "unknown"})');
      return [];
    }

    final sinceTs = since != null ? DateTime.tryParse(since) : null;
    final query = GenericSyncQueryBuilder.buildOutboundQuery(
      plan: plan,
      since: sinceTs,
      limit: 1000,
    );

    try {
      return await db.rawQuery(query.sql, query.args);
    } catch (e) {
      debugPrint('[WebSession] Query error on $table: $e');
      return [];
    }
  }

  Future<void> _ensureSyncPlans(Database db) async {
    if (_syncPlans.isNotEmpty) return;

    try {
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
      _syncPlans
        ..clear()
        ..addEntries(plans.map((p) => MapEntry(p.tableName, p)));
    } catch (e) {
      debugPrint('[WebSession] Failed to discover sync plans: $e');
    }
  }

}

