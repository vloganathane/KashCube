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

/// Placeholder for the future WebRTC DataChannel transport adapter.
///
/// This intentionally throws today so we can wire transport policy without
/// changing sync business logic before WebRTC signaling is implemented.
class WebRtcSyncTransportChannel implements SyncTransportChannel {
  final WebRtcNegotiationMailbox _mailbox = WebRtcNegotiationMailbox.instance;

  WebRtcNegotiationMailbox get mailbox => _mailbox;

  String? latestRemoteAnswerSdp(String sessionId) {
    return _mailbox.latestRemoteAnswerSdp(sessionId);
  }

  List<Map<String, dynamic>> drainRemoteIceCandidates(String sessionId) {
    return _mailbox.drainRemoteIceCandidates(sessionId);
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
