import 'dart:async';

import 'webrtc_negotiation_mailbox.dart';
import 'sync_transport_channel.dart';

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
