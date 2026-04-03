import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/services/database_helper.dart';
import '../../data/services/sync/generic_sync_query_builder.dart';
import '../../data/services/sync/transport/sync_signaling_messages.dart';
import '../../data/services/sync/sync_table_registry.dart';
import '../../data/services/sync/transport/sync_transport_channel.dart';
import '../../data/services/sync/transport/webrtc_negotiation_mailbox.dart';
import '../../data/services/sync/transport/webrtc_peer_ops.dart';
import '../../data/services/sync/transport/sync_transport_policy.dart';
import '../../data/services/sync/transport/webrtc_data_channel_bridge_shell.dart';
import '../../data/services/sync/transport/webrtc_sync_transport_channel.dart';
import '../../data/services/sync_event_bus.dart';
import '../web/web_url_reader_stub.dart'
    if (dart.library.js_interop) '../web/web_url_reader_web.dart'
    as url_reader;
import '../web/web_media_upload_stub.dart'
  if (dart.library.js_interop) '../web/web_media_upload_web.dart'
  as web_media_upload;
import '../web/web_preflight_probe_stub.dart'
  if (dart.library.js_interop) '../web/web_preflight_probe_web.dart'
  as web_preflight_probe;

// ── WebSocket connection state ─────────────────────────────────────────────

enum WsConnState { disconnected, connecting, connected }

enum WebAuthPhase {
  idle,
  serverReachable,
  wsReachable,
  challengeReceived,
  approved,
}

const _webSyncNoChange = Object();

class _PendingOutboundWrite {
  _PendingOutboundWrite({required Map<String, dynamic> payload})
      : payload = Map<String, dynamic>.from(payload);

  final Map<String, dynamic> payload;
  int attemptCount = 0;
  DateTime? lastSentAt;

  String get syncId => payload['sync_id']?.toString() ?? '';

  void markSent(DateTime sentAt) {
    attemptCount += 1;
    lastSentAt = sentAt;
  }
}

class WebSyncState {
  const WebSyncState({
    this.state        = WsConnState.disconnected,
    this.authPhase    = WebAuthPhase.idle,
    this.deviceName,
    this.errorMsg,
    this.progressMsg,
    this.syncedTables = const {},
    this.syncComplete = false,
    this.authQrPayload,
    this.awaitingApproval = false,
  });
  final WsConnState state;
  final WebAuthPhase authPhase;
  final String?     deviceName;
  final String?     errorMsg;
  final String?     progressMsg;

  /// Tables that have received their final ROWS frame from the phone.
  final Set<String> syncedTables;

  /// True once every discovered pull table has received is_final: true.
  final bool syncComplete;
  final String? authQrPayload;
  final bool awaitingApproval;

  WebSyncState copyWith({
    WsConnState? state,
    WebAuthPhase? authPhase,
    Object?      deviceName = _webSyncNoChange,
    Object?      errorMsg = _webSyncNoChange,
    Object?      progressMsg = _webSyncNoChange,
    Set<String>? syncedTables,
    bool?        syncComplete,
    Object?      authQrPayload = _webSyncNoChange,
    bool?        awaitingApproval,
  }) =>
      WebSyncState(
        state:        state        ?? this.state,
        authPhase: authPhase ?? this.authPhase,
        deviceName: identical(deviceName, _webSyncNoChange)
            ? this.deviceName
            : deviceName as String?,
        errorMsg: identical(errorMsg, _webSyncNoChange)
            ? this.errorMsg
            : errorMsg as String?,
        progressMsg: identical(progressMsg, _webSyncNoChange)
          ? this.progressMsg
          : progressMsg as String?,
        syncedTables: syncedTables ?? this.syncedTables,
        syncComplete: syncComplete ?? this.syncComplete,
        authQrPayload: identical(authQrPayload, _webSyncNoChange)
            ? this.authQrPayload
            : authQrPayload as String?,
        awaitingApproval: awaitingApproval ?? this.awaitingApproval,
      );
}

// ── Provider ───────────────────────────────────────────────────────────────

/// Manages the browser-side WebSocket connection to the phone.
/// Only used when running as a Flutter web app inside a browser.
///
/// On AUTH_OK, pulls all whitelisted tables via PULL messages and upserts
/// the resulting ROWS into the in-memory sqflite_common_ffi_web database.
/// PUSH messages (live phone writes) are also upserted incrementally.
/// All existing repositories read from [DatabaseHelper.instance.database]
/// unchanged — zero repo-layer changes required.
class WebSyncNotifier extends StateNotifier<WebSyncState> {
  static const String _peerOpsModeEnvKey = 'KASHCUBE_WEBRTC_PEER_OPS_MODE';

  static WebRtcPeerOpsMode resolveDefaultPeerOpsMode() {
    const configured = String.fromEnvironment(
      _peerOpsModeEnvKey,
      defaultValue: 'noop',
    );
    return parseWebRtcPeerOpsMode(configured);
  }

  WebSyncNotifier({
    bool preferWebRtcTransport = false,
    WebRtcPeerOpsMode? peerOpsMode,
    String? Function()? sessionIdProvider,
    Duration heartbeatReconnectBaseDelay = const Duration(seconds: 2),
    int maxHeartbeatReconnectAttempts = 3,
    Future<bool> Function(String wsUrl, String sessionId)? reconnectRunner,
    Duration writeAckTimeout = const Duration(seconds: 10),
    int maxWriteRetryAttempts = 3,
    int inboundDedupeCapacity = 512,
    Future<void> Function(String table, List<dynamic> rows)? upsertRowsHook,
    void Function(String table)? notifyChangeHook,
  })
      : _preferWebRtcTransport = preferWebRtcTransport,
        _peerOpsMode = peerOpsMode ?? resolveDefaultPeerOpsMode(),
        _sessionIdProvider = sessionIdProvider ?? url_reader.getSavedSessionId,
        _heartbeatReconnectBaseDelay = heartbeatReconnectBaseDelay,
        _maxHeartbeatReconnectAttempts = maxHeartbeatReconnectAttempts,
        _reconnectRunner = reconnectRunner,
        _writeAckTimeout = writeAckTimeout,
        _maxWriteRetryAttempts = maxWriteRetryAttempts,
        _inboundDedupeCapacity = inboundDedupeCapacity,
        _upsertRowsHook = upsertRowsHook,
        _notifyChangeHook = notifyChangeHook,
        super(const WebSyncState());

  SyncTransportChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  StreamSubscription<String>? _syncEventSub;
  Timer? _writeTimer;
  bool _writeLoopInFlight = false;
  bool _registrySnapshotLogged = false;
  String? _wsUrl; // remembered for session reconnect logging
  final bool _preferWebRtcTransport;
  final WebRtcPeerOpsMode _peerOpsMode;
  final String? Function() _sessionIdProvider;
  final Duration _heartbeatReconnectBaseDelay;
  final int _maxHeartbeatReconnectAttempts;
  final Future<bool> Function(String wsUrl, String sessionId)? _reconnectRunner;
  final Duration _writeAckTimeout;
  final int _maxWriteRetryAttempts;
  final int _inboundDedupeCapacity;
  final Future<void> Function(String table, List<dynamic> rows)? _upsertRowsHook;
  final void Function(String table)? _notifyChangeHook;
  Timer? _heartbeatReconnectTimer;
  int _heartbeatReconnectAttempts = 0;
  bool _heartbeatReconnectInFlight = false;
  final Map<String, _PendingOutboundWrite> _pendingOutboundWrites =
      <String, _PendingOutboundWrite>{};
    final Map<String, Set<String>> _seenInboundRowIdsByTable =
      <String, Set<String>>{};
    final Map<String, ListQueue<String>> _seenInboundRowOrderByTable =
      <String, ListQueue<String>>{};
  final Map<String, SyncTablePlan> _syncPlans = {};
  final Map<String, DateTime> _outboundLastSentAt = {};
  final Map<String, int>      _outboundLastSentVersion = {};
  final Set<String>           _snapshotSentTables = {};
  Set<String> _pullTables = const <String>{};
  final WebRtcNegotiationMailbox _webrtcMailbox =
      WebRtcNegotiationMailbox.instance;
  String? _latestRemoteAnswerSdp;
  final List<Map<String, dynamic>> _remoteIceCandidates = <Map<String, dynamic>>[];

  WebRtcPeerOpsFactory _buildWebRtcPeerOpsFactory() {
    return buildWebRtcPeerOpsFactory(_peerOpsMode);
  }

  /// Connect with a QR token (first load) or a session token (page refresh).
  ///
  /// Set [isSession] to true when passing a session token instead of a QR
  /// token — the phone will verify it with [SESSION_AUTH] handling.
  Future<void> connect(String wsUrl, String token,
      {bool isSession = false}) async {
    if (state.state == WsConnState.connecting ||
        state.state == WsConnState.connected) { return; }

    state = state.copyWith(
      state: WsConnState.connecting,
      authPhase: WebAuthPhase.idle,
      errorMsg: '',
      progressMsg: 'Opening secure local channel…',
      authQrPayload: null,
      awaitingApproval: false,
    );
    _wsUrl = wsUrl;

    try {
      final preflight = await web_preflight_probe.probePhoneHealth(wsUrl);
      if (!preflight.reachable) {
        state = state.copyWith(
          state: WsConnState.disconnected,
          authPhase: WebAuthPhase.idle,
          errorMsg: preflight.errorMessage,
          progressMsg: 'Phone server is not reachable',
          awaitingApproval: false,
        );
        return;
      }

      state = state.copyWith(
        authPhase: WebAuthPhase.serverReachable,
        progressMsg: 'Phone server reachable. Opening WebSocket…',
      );

      final uri = Uri.parse(wsUrl);
      _channel = await _connectTransport(uri);

      state = state.copyWith(
        authPhase: WebAuthPhase.wsReachable,
      );

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone:  _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      state = state.copyWith(progressMsg: 'Authenticating browser session…');

      // Send AUTH or SESSION_AUTH depending on credential type.
      _channel!.sendJson({
        'type':  isSession ? 'SESSION_AUTH' : 'AUTH',
        'token': token,
      });
    } catch (e) {
      state = state.copyWith(
        state:    WsConnState.disconnected,
        authPhase: WebAuthPhase.idle,
        errorMsg: 'Connection failed: $e',
        progressMsg: 'Could not open local channel',
      );
    }
  }

  Future<void> beginBrowserAuth(String wsUrl) async {
    if (state.state == WsConnState.connecting ||
        state.state == WsConnState.connected) {
      return;
    }

    state = state.copyWith(
      state: WsConnState.connecting,
      authPhase: WebAuthPhase.idle,
      errorMsg: '',
      progressMsg: 'Opening secure local channel…',
      authQrPayload: null,
      awaitingApproval: true,
    );
    _wsUrl = wsUrl;

    try {
      final preflight = await web_preflight_probe.probePhoneHealth(wsUrl);
      if (!preflight.reachable) {
        state = state.copyWith(
          state: WsConnState.disconnected,
          authPhase: WebAuthPhase.idle,
          errorMsg: preflight.errorMessage,
          progressMsg: 'Phone server is not reachable',
          awaitingApproval: false,
        );
        return;
      }

      state = state.copyWith(
        authPhase: WebAuthPhase.serverReachable,
        progressMsg: 'Phone server reachable. Opening WebSocket…',
      );

      final uri = Uri.parse(wsUrl);
      _channel = await _connectTransport(uri);

      state = state.copyWith(
        authPhase: WebAuthPhase.wsReachable,
      );

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      state = state.copyWith(progressMsg: 'Requesting phone approval QR…');

      _channel!.sendJson({'type': 'AUTH_BEGIN'});
    } catch (e) {
      state = state.copyWith(
        state: WsConnState.disconnected,
        authPhase: WebAuthPhase.idle,
        errorMsg: 'Connection failed: $e',
        progressMsg: 'Could not open local channel',
        awaitingApproval: false,
      );
    }
  }

  Future<SyncTransportChannel> _connectTransport(Uri uri) async {
    final preferred = SyncTransportPolicy.pick(
      preferWebRtc: _preferWebRtcTransport,
    );
    final preferredChannel = SyncTransportPolicy.create(
      preferred,
      peerOpsFactory: _buildWebRtcPeerOpsFactory(),
    );
    try {
      await preferredChannel.connect(uri);
      return preferredChannel;
    } catch (e) {
      if (preferred != SyncTransportKind.webRtc) rethrow;
      debugPrint('[WebSync] WebRTC transport unavailable, falling back to WebSocket: $e');

      final fallback = SyncTransportPolicy.create(SyncTransportKind.webSocket);
      await fallback.connect(uri);
      return fallback;
    }
  }

  /// Uploads a media blob to the connected phone over local HTTP and returns
  /// the assigned media_id, or null if upload cannot proceed.
  Future<String?> uploadMediaBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final wsUrl = _wsUrl;
    final sessionToken = url_reader.getSavedSessionId();
    if (wsUrl == null || sessionToken == null || sessionToken.isEmpty) {
      return null;
    }

    final result = await web_media_upload.uploadMedia(
      wsUrl: wsUrl,
      sessionToken: sessionToken,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    return result['media_id'] as String?;
  }

  void _onMessage(dynamic raw) {
    try {
      final msg  = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = (msg['type'] as String? ?? '').toUpperCase();
      switch (type) {
        case SyncSignalingMessages.authOk:
          unawaited(_handleAuthOk(msg));
          break;
        case SyncSignalingMessages.authChallenge:
          _handleAuthChallenge(msg);
          break;
        case SyncSignalingMessages.authFail:
          // Clear saved session so the user is prompted to scan a new QR.
          url_reader.clearSession();
          state = state.copyWith(
            state:    WsConnState.disconnected,
              authPhase: WebAuthPhase.idle,
            errorMsg: 'Authentication failed — scan a new QR code',
            progressMsg: 'Authentication failed',
            authQrPayload: null,
            awaitingApproval: false,
          );
          disconnect();
          break;
        case SyncSignalingMessages.ping:
          _channel?.sendJson({'type': 'PONG'});
          break;
        case SyncSignalingMessages.pong:
          // Keepalive acknowledgment for browser-initiated ping (if enabled).
          break;
        case SyncSignalingMessages.rows:
          _handleRows(msg);
          break;
        case SyncSignalingMessages.push:
          _handlePush(msg);
          break;
        case SyncSignalingMessages.writeOk:
          _handleWriteOk(msg);
          break;
        case SyncSignalingMessages.syncPlan:
          _handleSyncPlan(msg);
          break;
        case SyncSignalingMessages.signalOffer:
          debugPrint('[WebSync] SIGNAL_OFFER received - awaiting browser peer wiring');
          break;
        case SyncSignalingMessages.signalAnswer:
          _handleIncomingSignalAnswer(msg);
          break;
        case SyncSignalingMessages.signalIceCandidate:
          _handleIncomingIceCandidate(msg);
          break;
        case SyncSignalingMessages.signalAck:
          _handleSignalAck(msg);
          break;
        case SyncSignalingMessages.signalError:
          unawaited(_handleSignalError(msg));
          break;
        case SyncSignalingMessages.signalUnsupported:
          _handleSignalUnsupported(msg);
          break;
        case SyncSignalingMessages.webRtcRuntime:
          _handleWebRtcRuntime(msg);
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('[WebSync] Message parse error: $e');
    }
  }

  void _handleSignalAck(Map<String, dynamic> msg) {
    final sourceType = msg['source_type']?.toString() ?? 'unknown';
    final status = msg['status']?.toString() ?? 'accepted';
    state = state.copyWith(
      progressMsg: 'Signaling $sourceType: $status',
    );
    debugPrint('[WebSync] SIGNAL_ACK source=$sourceType status=$status');
  }

  void _handleIncomingSignalAnswer(Map<String, dynamic> msg) {
    _webrtcMailbox.ingestSignalingFrame(msg);

    final sdp = msg['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) {
      state = state.copyWith(
        errorMsg: 'Signaling answer frame missing sdp payload',
      );
      debugPrint('[WebSync] SIGNAL_ANSWER ignored: missing sdp');
      return;
    }

    _latestRemoteAnswerSdp = sdp;
    state = state.copyWith(
      progressMsg: 'Received answer SDP from phone',
    );

    _refreshWebRtcRuntimeState(msg['session_id']?.toString());
    debugPrint('[WebSync] SIGNAL_ANSWER received (length=${sdp.length})');
  }

  void _handleIncomingIceCandidate(Map<String, dynamic> msg) {
    _webrtcMailbox.ingestSignalingFrame(msg);

    final raw = msg['candidate'];
    if (raw is! Map) {
      debugPrint('[WebSync] SIGNAL_ICE_CANDIDATE ignored: malformed candidate');
      return;
    }

    final candidate = Map<String, dynamic>.from(raw);
    _remoteIceCandidates.add(candidate);

    final replayed = msg['replayed'] == true;
    final replayTag = replayed ? ' (replayed)' : '';
    state = state.copyWith(
      progressMsg: 'Received ICE candidate$replayTag from phone',
    );

    _refreshWebRtcRuntimeState(msg['session_id']?.toString());
    debugPrint(
      '[WebSync] SIGNAL_ICE_CANDIDATE received$replayTag '
      '(total=${_remoteIceCandidates.length})',
    );
  }

  void _refreshWebRtcRuntimeState(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      return;
    }

    final channel = _channel;
    if (channel is! WebRtcSyncTransportChannel) {
      return;
    }

    channel.syncRuntimeFromMailbox(sessionId: sessionId);
  }

  Future<void> _handleSignalError(Map<String, dynamic> msg) async {
    final code = msg['code']?.toString() ?? 'UNKNOWN_ERROR';
    final reason = msg['reason']?.toString() ?? 'Signaling error';
    state = state.copyWith(
      errorMsg: 'Signaling error ($code): $reason',
    );
    debugPrint('[WebSync] SIGNAL_ERROR code=$code reason=$reason');

    if (code == 'HEARTBEAT_TIMEOUT') {
      _scheduleHeartbeatReconnect(reason: reason);
    }
  }

  void _scheduleHeartbeatReconnect({required String reason}) {
    if (_heartbeatReconnectInFlight || _heartbeatReconnectTimer != null) {
      return;
    }
    if (_heartbeatReconnectAttempts >= _maxHeartbeatReconnectAttempts) {
      return;
    }

    final wsUrl = _wsUrl;
    final sessionId = _sessionIdProvider();
    if (wsUrl == null || wsUrl.isEmpty || sessionId == null || sessionId.isEmpty) {
      state = state.copyWith(
        progressMsg: 'Connection lost. Auto-reconnect unavailable.',
      );
      return;
    }

    final nextAttempt = _heartbeatReconnectAttempts + 1;
    final delay = Duration(
      milliseconds: _heartbeatReconnectBaseDelay.inMilliseconds * nextAttempt,
    );

    state = state.copyWith(
      progressMsg:
          'Connection unstable. Reconnecting ($nextAttempt/$_maxHeartbeatReconnectAttempts)…',
    );

    _heartbeatReconnectTimer = Timer(delay, () {
      _heartbeatReconnectTimer = null;
      unawaited(_attemptHeartbeatReconnect(wsUrl: wsUrl, sessionId: sessionId));
    });
  }

  Future<void> _attemptHeartbeatReconnect({
    required String wsUrl,
    required String sessionId,
  }) async {
    if (_heartbeatReconnectInFlight) {
      return;
    }

    _heartbeatReconnectInFlight = true;
    _heartbeatReconnectAttempts += 1;

    bool reconnected = false;
    try {
      final runner = _reconnectRunner ?? _defaultReconnectRunner;
      reconnected = await runner(wsUrl, sessionId);
    } catch (e) {
      debugPrint('[WebSync] Heartbeat reconnect attempt failed: $e');
      reconnected = false;
    } finally {
      _heartbeatReconnectInFlight = false;
    }

    if (reconnected) {
      _cancelHeartbeatReconnect(resetAttempts: true);
      state = state.copyWith(
        errorMsg: '',
        progressMsg: 'Reconnected after heartbeat timeout',
      );
      return;
    }

    if (_heartbeatReconnectAttempts >= _maxHeartbeatReconnectAttempts) {
      state = state.copyWith(
        progressMsg: 'Connection lost. Please reconnect.',
      );
      return;
    }

    _scheduleHeartbeatReconnect(reason: 'retry');
  }

  Future<bool> _defaultReconnectRunner(String wsUrl, String sessionId) async {
    disconnect(clearReconnectState: false);
    await connect(wsUrl, sessionId, isSession: true);
    return state.state == WsConnState.connected;
  }

  void _cancelHeartbeatReconnect({required bool resetAttempts}) {
    _heartbeatReconnectTimer?.cancel();
    _heartbeatReconnectTimer = null;
    _heartbeatReconnectInFlight = false;
    if (resetAttempts) {
      _heartbeatReconnectAttempts = 0;
    }
  }

  void _handleSignalUnsupported(Map<String, dynamic> msg) {
    final reason = msg['reason']?.toString() ?? 'WebRTC signaling not available';
    final code = msg['code']?.toString();
    final detail = (code == null || code.isEmpty) ? reason : '$reason ($code)';
    state = state.copyWith(
      progressMsg: 'Signaling fallback active: $detail',
    );
    debugPrint('[WebSync] SIGNAL_UNSUPPORTED $detail');
  }

  void _handleWebRtcRuntime(Map<String, dynamic> msg) {
    final sessionId = msg['session_id']?.toString() ?? 'unknown';
    final event = msg['event']?.toString() ?? 'UNKNOWN';

    switch (event) {
      case 'PEER_SESSION_CREATED':
        state = state.copyWith(
          progressMsg: 'WebRTC peer session created',
        );
        break;
      case 'DATA_CHANNEL_READY':
        state = state.copyWith(
          progressMsg: 'WebRTC data channel ready',
        );
        break;
      case 'PEER_SESSION_CLOSED':
        state = state.copyWith(
          progressMsg: 'WebRTC peer session closed',
        );
        break;
      default:
        state = state.copyWith(
          progressMsg: 'WebRTC runtime event: $event',
        );
        break;
    }

    debugPrint('[WebSync] WEBRTC_RUNTIME session=$sessionId event=$event');
  }

  Future<void> _handleAuthOk(Map<String, dynamic> msg) async {
    _cancelHeartbeatReconnect(resetAttempts: true);

    // Persist session token so a page refresh can re-authenticate without
    // requiring a new QR scan.  The phone rotates the session_id on every
    // successful auth, so we always save the freshest value.
    final sessionId = msg['session_id'] as String?;
    if (sessionId != null && _wsUrl != null) {
      url_reader.saveSession(sessionId, _wsUrl!);
    }

    final channel = _channel;
    if (sessionId != null && sessionId.isNotEmpty &&
        channel is WebRtcSyncTransportChannel) {
      channel.registerDataChannelBridge(
        sessionId: sessionId,
        bridge: WebRtcDataChannelBridgeShell(sessionId: sessionId),
      );
    }

    await _logDiscoveredSyncPlans();

    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();
    _snapshotSentTables.clear();
    final now = DateTime.now().toUtc();
    for (final plan in _outboundTables()) {
      switch (plan.mode) {
        case SyncMode.deltaTs:
          _outboundLastSentAt[plan.tableName] = now;
        case SyncMode.snapshot:
          // Never echo snapshot rows back to the phone — phone is authoritative.
          _snapshotSentTables.add(plan.tableName);
        case SyncMode.deltaVersion:
          // First flush will send from version 0; acceptable for infrequent tables.
          break;
      }
    }

    state = state.copyWith(
      state:        WsConnState.connected,
      authPhase: WebAuthPhase.approved,
      deviceName:   msg['device_name'] as String?,
      syncedTables: {},
      syncComplete: _pullTables.isEmpty,
      errorMsg:     '',
      progressMsg: _pullTables.isEmpty
          ? 'Connected'
          : 'Connected. Syncing local data…',
      authQrPayload: null,
      awaitingApproval: false,
    );

    _pullAllTables();
    _startWriteLoop();
  }

  void _handleAuthChallenge(Map<String, dynamic> msg) {
    state = state.copyWith(
      state: WsConnState.connecting,
      authPhase: WebAuthPhase.challengeReceived,
      authQrPayload: msg['qr_payload'] as String?,
      awaitingApproval: true,
      progressMsg: 'Scan this QR with your phone, then approve',
      errorMsg: '',
    );
  }

  /// Sends PULL requests for all whitelisted tables after AUTH_OK.
  /// No `since` filter — in-memory DB starts empty on every browser load.
  void _pullAllTables() {
    for (final table in _pullTables) {
      _channel?.sendJson({'type': 'PULL', 'table': table});
    }
  }

  Future<void> _logDiscoveredSyncPlans() async {
    if (_registrySnapshotLogged) return;
    _registrySnapshotLogged = true;
    try {
      final db = await DatabaseHelper.instance.database;
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(db);
      _syncPlans
        ..clear()
        ..addEntries(plans.map((p) => MapEntry(p.tableName, p)));
      // Only pull tables the browser is eligible to receive.
      _pullTables = plans
          .where((p) => p.isWebEligible)
          .map((p) => p.tableName)
          .toSet();
      final deltaTs = plans.where((p) => p.mode == SyncMode.deltaTs).length;
      final deltaVersion =
          plans.where((p) => p.mode == SyncMode.deltaVersion).length;
      final snapshot = plans.where((p) => p.mode == SyncMode.snapshot).length;

      debugPrint(
        '[SyncRegistry][Web] discovered=${plans.length} delta_ts=$deltaTs delta_version=$deltaVersion snapshot=$snapshot',
      );
    } catch (e) {
      debugPrint('[SyncRegistry][Web] discovery failed: $e');
    }
  }

  /// Handles a ROWS frame: upserts rows into in-memory SQLite, marks the
  /// table done when is_final is true. Emits syncComplete when all tables
  /// have received their final frame.
  Future<void> _handleRows(Map<String, dynamic> msg) async {
    final table   = msg['table']    as String?;
    final rows    = msg['rows']     as List<dynamic>?;
    final isFinal = msg['is_final'] as bool? ?? false;

    if (table == null || rows == null) return;

    final filteredRows = _filterNewInboundRows(table, rows);

    if (filteredRows.isNotEmpty) {
      await _mergeInboundRows(table, filteredRows);
      _markOutboundWatermarkFromRows(table, filteredRows);
      _notifyTableChanged(table);
    }

    if (isFinal) {
      final updated = {...state.syncedTables, table};
      final done = _pullTables.every(updated.contains);
      state = state.copyWith(
        syncedTables: updated,
        syncComplete: done,
        progressMsg: done ? 'Connected and synced' : 'Syncing local data…',
      );
      debugPrint('[WebSync] Table synced: $table (all done: $done)');
    }
  }

  /// Handles a PUSH frame (live phone write): upserts rows incrementally.
  Future<void> _handlePush(Map<String, dynamic> msg) async {
    final table = msg['table'] as String?;
    final rows  = msg['rows']  as List<dynamic>?;
    if (table == null || rows == null || rows.isEmpty) return;
    final filteredRows = _filterNewInboundRows(table, rows);
    if (filteredRows.isEmpty) {
      debugPrint('[WebSync] PUSH deduped: $table (${rows.length} duplicate row(s))');
      return;
    }

    await _mergeInboundRows(table, filteredRows);
    _markOutboundWatermarkFromRows(table, filteredRows);
    _notifyTableChanged(table);
    debugPrint('[WebSync] PUSH: $table (${filteredRows.length} row(s))');
  }

  List<dynamic> _filterNewInboundRows(String table, List<dynamic> rows) {
    final seenIds = _seenInboundRowIdsByTable.putIfAbsent(
      table,
      () => <String>{},
    );
    final seenOrder = _seenInboundRowOrderByTable.putIfAbsent(
      table,
      () => ListQueue<String>(),
    );

    final filtered = <dynamic>[];
    for (final row in rows) {
      if (row is! Map) {
        filtered.add(row);
        continue;
      }

      final syncId = row['sync_id']?.toString();
      if (syncId == null || syncId.isEmpty) {
        filtered.add(row);
        continue;
      }
      if (seenIds.contains(syncId)) {
        continue;
      }

      seenIds.add(syncId);
      seenOrder.addLast(syncId);
      while (seenOrder.length > _inboundDedupeCapacity) {
        final evicted = seenOrder.removeFirst();
        seenIds.remove(evicted);
      }
      filtered.add(row);
    }

    return filtered;
  }

  Future<void> _mergeInboundRows(String table, List<dynamic> rows) async {
    final hook = _upsertRowsHook;
    if (hook != null) {
      await hook(table, rows);
      return;
    }

    await _upsertRows(table, rows);
  }

  void _notifyTableChanged(String table) {
    final hook = _notifyChangeHook;
    if (hook != null) {
      hook(table);
      return;
    }

    DatabaseHelper.instance.notifyChange(table);
  }

  /// Handles the phone's SYNC_PLAN message: logs the advertised tables so
  /// we can verify alignment with the browser's own discovery.
  void _handleSyncPlan(Map<String, dynamic> msg) {
    final tables = msg['tables'] as List<dynamic>? ?? [];
    debugPrint('[WebSync] Phone SYNC_PLAN: ${tables.length} table(s)');
    for (final entry in tables) {
      if (entry is Map<String, dynamic>) {
        final name = entry['name'] as String? ?? '?';
        final mode = entry['mode'] as String? ?? '?';
        debugPrint('[WebSync]   ↳ $name ($mode)');
      }
    }
  }

  void _startWriteLoop() {
    _writeTimer?.cancel();
    _writeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _flushLocalWritesToPhone();
    });
    // Trigger immediately whenever a local table changes.
    _syncEventSub?.cancel();
    _syncEventSub = SyncEventBus.instance.stream.listen((table) {
      _flushLocalWritesToPhone();
    });
  }

  Future<void> _flushLocalWritesToPhone() async {
    if (_writeLoopInFlight) {
      return;
    }
    if (state.state != WsConnState.connected || _channel == null) {
      return;
    }
    _writeLoopInFlight = true;

    try {
      _retryPendingWrites();

      final db = await DatabaseHelper.instance.database;
      for (final plan in _outboundTables()) {
        final table = plan.tableName;
        if (plan.mode == SyncMode.snapshot && _snapshotSentTables.contains(table)) {
          continue;
        }

        final query = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: plan,
          since: plan.mode == SyncMode.deltaTs ? _outboundLastSentAt[table] : null,
          afterVersion: plan.mode == SyncMode.deltaVersion
              ? _outboundLastSentVersion[table]
              : null,
        );
        final rows = await db.rawQuery(query.sql, query.args);
        if (rows.isEmpty) continue;

        for (final row in rows) {
          final normalized = Map<String, dynamic>.from(row);
          normalized['sync_id'] ??= _newSyncId();
          _queueOutboundWrite(<String, dynamic>{
            'type': 'WRITE',
            'table': table,
            'sync_id': normalized['sync_id'],
            'row': normalized,
          });
        }

        // Advance watermark after successful push.
        switch (plan.mode) {
          case SyncMode.deltaTs:
            _outboundLastSentAt[table] = GenericSyncQueryBuilder.maxTimestamp(rows);
          case SyncMode.deltaVersion:
            final maxV = GenericSyncQueryBuilder.maxVersion(rows);
            if (maxV != null) _outboundLastSentVersion[table] = maxV;
          case SyncMode.snapshot:
            _snapshotSentTables.add(table);
        }
      }
    } catch (e) {
      debugPrint('[WebSync] Outbound WRITE loop error: $e');
    } finally {
      _writeLoopInFlight = false;
    }
  }

  void _queueOutboundWrite(Map<String, dynamic> payload) {
    final syncId = payload['sync_id']?.toString();
    if (syncId == null || syncId.isEmpty) {
      return;
    }

    final pending = _pendingOutboundWrites.putIfAbsent(
      syncId,
      () => _PendingOutboundWrite(payload: payload),
    );
    if (pending.attemptCount > 0) {
      return;
    }

    _sendPendingWrite(pending, isRetry: false);
  }

  void _retryPendingWrites() {
    final now = DateTime.now().toUtc();
    for (final pending in _pendingOutboundWrites.values) {
      final lastSentAt = pending.lastSentAt;
      if (lastSentAt == null) {
        _sendPendingWrite(pending, isRetry: false);
        continue;
      }

      if (now.difference(lastSentAt) < _writeAckTimeout) {
        continue;
      }

      if (pending.attemptCount >= _maxWriteRetryAttempts) {
        state = state.copyWith(
          progressMsg: 'Write delivery pending confirmation. Reconnect may be required.',
        );
        continue;
      }

      _sendPendingWrite(pending, isRetry: true);
    }
  }

  void _sendPendingWrite(_PendingOutboundWrite pending, {required bool isRetry}) {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    final payload = Map<String, dynamic>.from(pending.payload)
      ..['retry_count'] = pending.attemptCount;
    if (isRetry) {
      payload['is_retry'] = true;
    }

    channel.sendJson(payload);
    pending.markSent(DateTime.now().toUtc());
  }

  void _handleWriteOk(Map<String, dynamic> msg) {
    final syncId = msg['sync_id']?.toString();
    if (syncId == null || syncId.isEmpty) {
      return;
    }

    _pendingOutboundWrites.remove(syncId);
  }

  List<SyncTablePlan> _outboundTables() {
    return _syncPlans.values
        .where((plan) => plan.isWebEligible)
        .toList()
      ..sort((a, b) => a.tableName.compareTo(b.tableName));
  }

  void _markOutboundWatermarkFromRows(String table, List<dynamic> rows) {
    if (rows.isEmpty) return;
    var maxTs = _outboundLastSentAt[table] ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    for (final row in rows) {
      if (row is! Map) continue;
      final map = row;
      final updatedRaw = map['updated_at']?.toString();
      final createdRaw = map['created_at']?.toString();
      final ts = DateTime.tryParse(updatedRaw ?? '') ??
          DateTime.tryParse(createdRaw ?? '');
      if (ts != null && ts.toUtc().isAfter(maxTs)) {
        maxTs = ts.toUtc();
      }
    }

    _outboundLastSentAt[table] = maxTs;
  }

  String _newSyncId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    return '${now.toRadixString(16)}$rand';
  }

  /// Bulk-upserts [rows] into the in-memory SQLite using INSERT OR REPLACE.
  /// Strips any columns that don't exist in the target table (e.g. rows from
  /// an older phone schema where column names have since been renamed).
  Future<void> _upsertRows(String table, List<dynamic> rows) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
      final validCols = tableInfo.map((r) => r['name'] as String).toSet();
      final batch = db.batch();
      for (final r in rows) {
        if (r is Map<String, dynamic>) {
          final filtered = Map<String, dynamic>.fromEntries(
            r.entries.where((e) => validCols.contains(e.key)),
          );
          if (filtered.isNotEmpty) {
            batch.insert(
              table,
              filtered,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[WebSync] Upsert error for $table: $e');
    }
  }

  void _onDisconnected() {
    state = state.copyWith(
      state:      WsConnState.disconnected,
      authPhase: WebAuthPhase.idle,
      deviceName: null,
      progressMsg: 'Disconnected',
      authQrPayload: null,
      awaitingApproval: false,
    );
  }

  /// Explicit user logout from browser side.
  /// Clears session-storage token and closes the socket.
  void logout() {
    url_reader.clearSession();
    disconnect();
  }

  bool get canSendSignaling {
    final sessionId = url_reader.getSavedSessionId();
    return state.state == WsConnState.connected &&
        _channel != null &&
        sessionId != null &&
        sessionId.isNotEmpty;
  }

  String? get latestRemoteAnswerSdp => _latestRemoteAnswerSdp;

  List<Map<String, dynamic>> get remoteIceCandidates =>
      List<Map<String, dynamic>>.unmodifiable(_remoteIceCandidates);

  void sendSignalOffer({required String sdp}) {
    final sessionId = url_reader.getSavedSessionId();
    if (sessionId != null && sessionId.isNotEmpty) {
      _webrtcMailbox.stageLocalOffer(sessionId: sessionId, offerSdp: sdp);
    }

    _sendSignalFrame(
      type: SyncSignalingMessages.signalOffer,
      payload: {'sdp': sdp},
    );
  }

  void sendSignalAnswer({required String sdp}) {
    _sendSignalFrame(
      type: SyncSignalingMessages.signalAnswer,
      payload: {'sdp': sdp},
    );
  }

  void sendSignalIceCandidate({required Map<String, dynamic> candidate}) {
    _sendSignalFrame(
      type: SyncSignalingMessages.signalIceCandidate,
      payload: {'candidate': candidate},
    );
  }

  void _sendSignalFrame({
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final sessionId = url_reader.getSavedSessionId();
    if (state.state != WsConnState.connected || _channel == null) {
      state = state.copyWith(errorMsg: 'Cannot send signaling frame while disconnected');
      return;
    }
    if (sessionId == null || sessionId.isEmpty) {
      state = state.copyWith(errorMsg: 'Missing session id for signaling');
      return;
    }

    final signalId = _newSyncId();
    _channel!.sendJson({
      'type': type,
      'session_id': sessionId,
      'signal_id': signalId,
      ...payload,
    });

    state = state.copyWith(progressMsg: 'Sending signaling frame: $type');
    debugPrint('[WebSync] Sent signaling frame type=$type signal_id=$signalId');
  }

  @visibleForTesting
  void setWsUrlForTest(String wsUrl) {
    _wsUrl = wsUrl;
  }

  @visibleForTesting
  void setChannelForTest(SyncTransportChannel channel) {
    _channel = channel;
    state = state.copyWith(state: WsConnState.connected, errorMsg: '');
  }

  @visibleForTesting
  void ingestMessageForTest(Map<String, dynamic> message) {
    _onMessage(jsonEncode(message));
  }

  @visibleForTesting
  void enqueueOutboundWriteForTest(Map<String, dynamic> payload) {
    _queueOutboundWrite(payload);
  }

  @visibleForTesting
  void retryPendingWritesForTest() {
    _retryPendingWrites();
  }

  @visibleForTesting
  int get pendingOutboundWriteCountForTest => _pendingOutboundWrites.length;

  void disconnect({bool clearReconnectState = true}) {
    if (clearReconnectState) {
      _cancelHeartbeatReconnect(resetAttempts: true);
    }
    _writeTimer?.cancel();
    _writeTimer = null;
    _syncEventSub?.cancel();
    _syncEventSub = null;
    _syncPlans.clear();
    _pullTables = const <String>{};
    final sessionId = url_reader.getSavedSessionId();
    if (sessionId != null && sessionId.isNotEmpty) {
      _webrtcMailbox.clearSession(sessionId);
      final channel = _channel;
      if (channel is WebRtcSyncTransportChannel) {
        unawaited(channel.unregisterDataChannelBridge(sessionId));
        channel.clearPeerRuntime(sessionId);
      }
    }
    _latestRemoteAnswerSdp = null;
    _remoteIceCandidates.clear();
    _pendingOutboundWrites.clear();
    _seenInboundRowIdsByTable.clear();
    _seenInboundRowOrderByTable.clear();
    _outboundLastSentAt.clear();
    _outboundLastSentVersion.clear();
    _snapshotSentTables.clear();
    _sub?.cancel();
    unawaited(_channel?.close());
    _channel = null;
    _onDisconnected();
  }

  @override
  void dispose() {
    disconnect(clearReconnectState: true);
    super.dispose();
  }
}

final webSyncProvider =
    StateNotifierProvider<WebSyncNotifier, WebSyncState>(
  (_) => WebSyncNotifier(),
);
