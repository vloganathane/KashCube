import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'sync_signaling_messages.dart';
import 'webrtc_data_channel_bridge_shell.dart';
import 'webrtc_negotiation_mailbox.dart';
import 'webrtc_peer_ops.dart';
import 'sync_transport_channel.dart';
import 'websocket_sync_transport_channel.dart';

class WebRtcNegotiationSnapshot {
  const WebRtcNegotiationSnapshot({
    required this.sessionId,
    this.localOfferSdp,
    this.remoteAnswerSdp,
    this.remoteIceCandidates = const <Map<String, dynamic>>[],
  });

  final String sessionId;
  final String? localOfferSdp;
  final String? remoteAnswerSdp;
  final List<Map<String, dynamic>> remoteIceCandidates;

  bool get hasOffer => localOfferSdp != null && localOfferSdp!.isNotEmpty;
  bool get hasAnswer => remoteAnswerSdp != null && remoteAnswerSdp!.isNotEmpty;
  bool get hasIceCandidates => remoteIceCandidates.isNotEmpty;
}

class WebRtcPeerRuntimeState {
  const WebRtcPeerRuntimeState({
    required this.sessionId,
    this.localOfferSdp,
    this.remoteAnswerSdp,
    this.remoteIceCandidates = const <Map<String, dynamic>>[],
  });

  final String sessionId;
  final String? localOfferSdp;
  final String? remoteAnswerSdp;
  final List<Map<String, dynamic>> remoteIceCandidates;

  bool get hasOffer => localOfferSdp != null && localOfferSdp!.isNotEmpty;
  bool get hasAnswer => remoteAnswerSdp != null && remoteAnswerSdp!.isNotEmpty;
  int get remoteIceCount => remoteIceCandidates.length;
}

abstract class WebRtcPeerRuntime {
  String get sessionId;

  WebRtcPeerRuntimeState get state;

  void applyLocalOffer(String sdp);

  void applyRemoteAnswer(String sdp);

  void addRemoteIceCandidate(Map<String, dynamic> candidate);
}

/// Bridge contract between transport wrapper and concrete WebRTC data channel.
///
/// A future flutter_webrtc implementation can implement this interface and be
/// registered per session via [registerDataChannelBridge].
abstract class WebRtcDataChannelBridge {
  Stream<String> get inboundFrames;

  Future<void> sendFrame(String jsonFrame);

  Future<void> close();
}

/// Optional capabilities for bridges that can accept negotiation artifacts.
abstract class WebRtcNegotiationAwareBridge implements WebRtcDataChannelBridge {
  void applyLocalOfferSdp(String sdp);

  void applyRemoteAnswerSdp(String sdp);

  void addRemoteIceCandidate(Map<String, dynamic> candidate);
}

/// Minimal placeholder bridge for session lifecycle wiring.
///
/// This keeps registration/unregistration paths deterministic before the
/// concrete flutter_webrtc DataChannel bridge is available.
class NoopWebRtcDataChannelBridge implements WebRtcDataChannelBridge {
  @override
  Stream<String> get inboundFrames => const Stream<String>.empty();

  @override
  Future<void> sendFrame(String jsonFrame) async {}

  @override
  Future<void> close() async {}
}

class InMemoryWebRtcPeerRuntime implements WebRtcPeerRuntime {
  InMemoryWebRtcPeerRuntime({required this.sessionId});

  @override
  final String sessionId;

  String? _localOfferSdp;
  String? _remoteAnswerSdp;
  final List<Map<String, dynamic>> _remoteIceCandidates =
      <Map<String, dynamic>>[];

  @override
  WebRtcPeerRuntimeState get state => WebRtcPeerRuntimeState(
    sessionId: sessionId,
    localOfferSdp: _localOfferSdp,
    remoteAnswerSdp: _remoteAnswerSdp,
    remoteIceCandidates: List<Map<String, dynamic>>.unmodifiable(
      _remoteIceCandidates,
    ),
  );

  @override
  void applyLocalOffer(String sdp) {
    if (sdp.isEmpty) return;
    _localOfferSdp = sdp;
  }

  @override
  void applyRemoteAnswer(String sdp) {
    if (sdp.isEmpty) return;
    _remoteAnswerSdp = sdp;
  }

  @override
  void addRemoteIceCandidate(Map<String, dynamic> candidate) {
    if (candidate.isEmpty) return;
    _remoteIceCandidates.add(Map<String, dynamic>.from(candidate));
  }
}

/// Hybrid transport adapter that keeps WebSocket as control plane while
/// activating WebRTC DataChannel for eligible sync payloads once ready.
class WebRtcSyncTransportChannel implements SyncTransportChannel {
  WebRtcSyncTransportChannel({
    WebRtcPeerOpsFactory? peerOpsFactory,
    SyncTransportChannel? controlPlaneChannel,
    Duration heartbeatInterval = const Duration(seconds: 15),
    Duration heartbeatTimeout = const Duration(seconds: 45),
  }) : _peerOpsFactory = peerOpsFactory ?? ((_) => NoopWebRtcPeerOps()),
       _controlPlaneChannel =
           controlPlaneChannel ?? WebSocketSyncTransportChannel(),
       _heartbeatInterval = heartbeatInterval,
       _heartbeatTimeout = heartbeatTimeout;

  final WebRtcNegotiationMailbox _mailbox = WebRtcNegotiationMailbox.instance;
  final WebRtcPeerOpsFactory _peerOpsFactory;
  final SyncTransportChannel _controlPlaneChannel;
  final Duration _heartbeatInterval;
  final Duration _heartbeatTimeout;
  final Map<String, WebRtcPeerRuntime> _runtimeBySession =
      <String, WebRtcPeerRuntime>{};
  final Map<String, WebRtcDataChannelBridge> _bridgeBySession =
      <String, WebRtcDataChannelBridge>{};
  final StreamController<dynamic> _inboundController =
      StreamController<dynamic>.broadcast();
  StreamSubscription<dynamic>? _controlPlaneSub;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeatSentAt;
  bool _awaitingHeartbeatPong = false;
  bool _heartbeatTimeoutEmitted = false;

  String? _activeSessionId;

  WebRtcNegotiationMailbox get mailbox => _mailbox;

  String? latestRemoteAnswerSdp(String sessionId) {
    return _mailbox.latestRemoteAnswerSdp(sessionId);
  }

  List<Map<String, dynamic>> drainRemoteIceCandidates(String sessionId) {
    return _mailbox.drainRemoteIceCandidates(sessionId);
  }

  WebRtcPeerRuntime ensurePeerRuntime(String sessionId) {
    return _runtimeBySession.putIfAbsent(
      sessionId,
      () => InMemoryWebRtcPeerRuntime(sessionId: sessionId),
    );
  }

  /// Build a deterministic negotiation snapshot for a session.
  ///
  /// This is consumed by the future WebRTC peer runtime initializer to attach
  /// staged signaling artifacts (offer, answer, ICE) to RTCPeerConnection.
  WebRtcNegotiationSnapshot negotiationSnapshot({
    required String sessionId,
    bool drainIce = false,
  }) {
    final offerSdp = _mailbox.localOfferSdp(sessionId);
    final answerSdp = _mailbox.latestRemoteAnswerSdp(sessionId);
    final ice = drainIce
        ? _mailbox.drainRemoteIceCandidates(sessionId)
        : _mailbox.remoteIceCandidates(sessionId);

    final snapshot = WebRtcNegotiationSnapshot(
      sessionId: sessionId,
      localOfferSdp: offerSdp,
      remoteAnswerSdp: answerSdp,
      remoteIceCandidates: ice,
    );

    debugPrint(
      '[WebRtcSyncTransportChannel] Snapshot built for session $sessionId '
      '(offer=${snapshot.hasOffer}, answer=${snapshot.hasAnswer}, '
      'ice=${snapshot.remoteIceCandidates.length})',
    );

    return snapshot;
  }

  /// Sync mailbox-staged artifacts into the session runtime.
  ///
  /// This forms the initial bridge before wiring a concrete RTCPeerConnection.
  WebRtcPeerRuntimeState syncRuntimeFromMailbox({
    required String sessionId,
    bool drainIce = true,
  }) {
    final runtime = ensurePeerRuntime(sessionId);
    final snapshot = negotiationSnapshot(
      sessionId: sessionId,
      drainIce: drainIce,
    );

    if (snapshot.localOfferSdp != null) {
      runtime.applyLocalOffer(snapshot.localOfferSdp!);
    }
    if (snapshot.remoteAnswerSdp != null) {
      runtime.applyRemoteAnswer(snapshot.remoteAnswerSdp!);
    }
    for (final candidate in snapshot.remoteIceCandidates) {
      runtime.addRemoteIceCandidate(candidate);
    }

    final state = runtime.state;
    _syncBridgeFromRuntime(sessionId: sessionId, state: state);

    debugPrint(
      '[WebRtcSyncTransportChannel] Runtime sync complete for session '
      '$sessionId (offer=${state.hasOffer}, answer=${state.hasAnswer}, '
      'ice=${state.remoteIceCount})',
    );
    return state;
  }

  void clearPeerRuntime(String sessionId) {
    _runtimeBySession.remove(sessionId);
  }

  /// Register a concrete data channel bridge for a session.
  void registerDataChannelBridge({
    required String sessionId,
    required WebRtcDataChannelBridge bridge,
  }) {
    _bridgeBySession[sessionId] = bridge;
    _activeSessionId = sessionId;

    bridge.inboundFrames.listen((raw) {
      _inboundController.add(raw);
    });

    _attachDefaultPeerOpsIfNeeded(sessionId: sessionId, bridge: bridge);

    final runtime = _runtimeBySession[sessionId];
    if (runtime != null) {
      _syncBridgeFromRuntime(sessionId: sessionId, state: runtime.state);
    }
  }

  void _attachDefaultPeerOpsIfNeeded({
    required String sessionId,
    required WebRtcDataChannelBridge bridge,
  }) {
    if (bridge is! WebRtcDataChannelBridgeShell || bridge.hasPeerOps) {
      return;
    }

    unawaited(bridge.attachPeerOps(_peerOpsFactory(sessionId)));
  }

  void _syncBridgeFromRuntime({
    required String sessionId,
    required WebRtcPeerRuntimeState state,
  }) {
    final bridge = _bridgeBySession[sessionId];
    if (bridge is! WebRtcNegotiationAwareBridge) {
      return;
    }

    if (state.localOfferSdp != null && state.localOfferSdp!.isNotEmpty) {
      bridge.applyLocalOfferSdp(state.localOfferSdp!);
    }
    if (state.remoteAnswerSdp != null && state.remoteAnswerSdp!.isNotEmpty) {
      bridge.applyRemoteAnswerSdp(state.remoteAnswerSdp!);
    }
    for (final candidate in state.remoteIceCandidates) {
      bridge.addRemoteIceCandidate(candidate);
    }
  }

  Future<void> unregisterDataChannelBridge(String sessionId) async {
    final bridge = _bridgeBySession.remove(sessionId);
    if (bridge != null) {
      await bridge.close();
    }
    if (_activeSessionId == sessionId) {
      _activeSessionId = null;
    }
  }

  @override
  Future<void> connect(Uri uri) async {
    await _controlPlaneChannel.connect(uri);
    await _controlPlaneSub?.cancel();
    _controlPlaneSub = _controlPlaneChannel.stream.listen((raw) {
      _onInboundControlPlaneFrame(raw);
      _inboundController.add(raw);
    });
    _startHeartbeat();
  }

  @override
  Stream<dynamic> get stream => _inboundController.stream;

  @override
  void sendJson(Map<String, dynamic> payload) {
    final type = payload['type']?.toString().toUpperCase() ?? '';
    final targetSessionId = _resolveTargetSessionId(payload);
    if (SyncSignalingMessages.isControlPlaneType(type)) {
      _controlPlaneChannel.sendJson(payload);
      return;
    }

    if (_shouldUseDataPlane(type: type, sessionId: targetSessionId)) {
      unawaited(
        _sendViaDataPlane(payload: payload, sessionId: targetSessionId),
      );
      return;
    }

    _controlPlaneChannel.sendJson(payload);
  }

  String? _resolveTargetSessionId(Map<String, dynamic> payload) {
    final payloadSessionId = payload['session_id']?.toString().trim();
    if (payloadSessionId != null && payloadSessionId.isNotEmpty) {
      return payloadSessionId;
    }

    return _activeSessionId;
  }

  bool _shouldUseDataPlane({required String type, required String? sessionId}) {
    if (!SyncSignalingMessages.isDataPlaneEligibleType(type)) {
      return false;
    }

    if (sessionId == null || sessionId.isEmpty) {
      return false;
    }

    final bridge = _bridgeBySession[sessionId];
    return bridge is WebRtcDataChannelBridgeShell && bridge.isDataChannelReady;
  }

  Future<void> _sendViaDataPlane({
    required Map<String, dynamic> payload,
    required String? sessionId,
  }) async {
    if (sessionId == null || sessionId.isEmpty) {
      _controlPlaneChannel.sendJson(payload);
      return;
    }

    final bridge = _bridgeBySession[sessionId];
    if (bridge == null) {
      _controlPlaneChannel.sendJson(payload);
      return;
    }

    final frame = jsonEncode(payload);
    try {
      await bridge.sendFrame(frame);
    } catch (_) {
      // Preserve delivery by falling back to control plane when DataChannel send fails.
      _controlPlaneChannel.sendJson(payload);
    }
  }

  @override
  Future<void> close() async {
    final sessions = _bridgeBySession.keys.toList();
    for (final sessionId in sessions) {
      await unregisterDataChannelBridge(sessionId);
    }
    _stopHeartbeat();
    await _controlPlaneSub?.cancel();
    _controlPlaneSub = null;
    await _controlPlaneChannel.close();
    await _inboundController.close();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _awaitingHeartbeatPong = false;
    _heartbeatTimeoutEmitted = false;
    _lastHeartbeatSentAt = null;

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final now = DateTime.now();
      if (_awaitingHeartbeatPong && _lastHeartbeatSentAt != null) {
        final elapsed = now.difference(_lastHeartbeatSentAt!);
        if (elapsed >= _heartbeatTimeout && !_heartbeatTimeoutEmitted) {
          _heartbeatTimeoutEmitted = true;
          _inboundController.add(
            jsonEncode(<String, dynamic>{
              'type': SyncSignalingMessages.signalError,
              'code': 'HEARTBEAT_TIMEOUT',
              'reason': 'Control plane heartbeat timeout',
            }),
          );
          debugPrint('[WebRtcSyncTransportChannel] Heartbeat timeout detected');
        }

        // Do not overwrite the outstanding ping timestamp until a PONG arrives.
        return;
      }

      _controlPlaneChannel.sendJson(<String, dynamic>{
        'type': SyncSignalingMessages.ping,
      });
      _awaitingHeartbeatPong = true;
      _lastHeartbeatSentAt = now;
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _awaitingHeartbeatPong = false;
    _heartbeatTimeoutEmitted = false;
    _lastHeartbeatSentAt = null;
  }

  void _onInboundControlPlaneFrame(dynamic raw) {
    final type = _extractFrameType(raw);
    if (type == SyncSignalingMessages.pong) {
      _awaitingHeartbeatPong = false;
      _heartbeatTimeoutEmitted = false;
    }
  }

  String? _extractFrameType(dynamic raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final type = decoded['type']?.toString();
      if (type == null || type.isEmpty) {
        return null;
      }
      return type.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}
