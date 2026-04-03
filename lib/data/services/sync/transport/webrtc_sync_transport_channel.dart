import 'dart:async';

import 'package:flutter/foundation.dart';

import 'webrtc_negotiation_mailbox.dart';
import 'sync_transport_channel.dart';

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

/// Placeholder for the future WebRTC DataChannel transport adapter.
///
/// This intentionally throws today so we can wire transport policy without
/// changing sync business logic before WebRTC signaling is implemented.
class WebRtcSyncTransportChannel implements SyncTransportChannel {
  final WebRtcNegotiationMailbox _mailbox = WebRtcNegotiationMailbox.instance;
  final Map<String, WebRtcPeerRuntime> _runtimeBySession =
      <String, WebRtcPeerRuntime>{};

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
    final snapshot = negotiationSnapshot(sessionId: sessionId, drainIce: drainIce);

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

  @override
  Future<void> connect(Uri uri) async {
    throw UnsupportedError(
      'WebRTC transport is not implemented yet. '
      'Complete signaling + ICE exchange before enabling this policy.',
    );
  }

  @override
  Stream<dynamic> get stream => const Stream<dynamic>.empty();

  @override
  void sendJson(Map<String, dynamic> payload) {
    throw StateError('WebRTC transport is not connected');
  }

  @override
  Future<void> close() async {}
}
