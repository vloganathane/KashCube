import 'dart:collection';

import 'sync_signaling_messages.dart';

/// In-memory mailbox that bridges signaling-plane messages and future
/// WebRTC DataChannel runtime wiring.
///
/// Browser/provider writes inbound signaling artifacts (answer SDP + remote ICE)
/// into this mailbox. A future WebRTC peer runtime can read and drain these
/// values per session without coupling directly to UI/provider state.
class WebRtcNegotiationMailbox {
  WebRtcNegotiationMailbox._();

  static final WebRtcNegotiationMailbox instance = WebRtcNegotiationMailbox._();

  final Map<String, String> _remoteAnswerBySession = <String, String>{};
  final Map<String, List<Map<String, dynamic>>> _remoteIceBySession =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, String> _localOfferBySession = <String, String>{};

  void stageLocalOffer({required String sessionId, required String offerSdp}) {
    if (sessionId.isEmpty || offerSdp.isEmpty) return;
    _localOfferBySession[sessionId] = offerSdp;
  }

  void ingestSignalingFrame(Map<String, dynamic> frame) {
    final type = frame['type']?.toString();
    final sessionId = frame['session_id']?.toString();
    if (type == null || sessionId == null || sessionId.isEmpty) {
      return;
    }

    switch (type) {
      case SyncSignalingMessages.signalAnswer:
        final sdp = frame['sdp']?.toString();
        if (sdp != null && sdp.isNotEmpty) {
          _remoteAnswerBySession[sessionId] = sdp;
        }
        break;
      case SyncSignalingMessages.signalIceCandidate:
        final raw = frame['candidate'];
        if (raw is Map) {
          final list = _remoteIceBySession.putIfAbsent(
            sessionId,
            () => <Map<String, dynamic>>[],
          );
          list.add(Map<String, dynamic>.from(raw));
        }
        break;
      default:
        break;
    }
  }

  String? latestRemoteAnswerSdp(String sessionId) {
    return _remoteAnswerBySession[sessionId];
  }

  List<Map<String, dynamic>> remoteIceCandidates(String sessionId) {
    final list = _remoteIceBySession[sessionId] ?? const <Map<String, dynamic>>[];
    return UnmodifiableListView<Map<String, dynamic>>(list);
  }

  List<Map<String, dynamic>> drainRemoteIceCandidates(String sessionId) {
    final list = _remoteIceBySession.remove(sessionId) ?? <Map<String, dynamic>>[];
    return list;
  }

  String? localOfferSdp(String sessionId) {
    return _localOfferBySession[sessionId];
  }

  void clearSession(String sessionId) {
    _remoteAnswerBySession.remove(sessionId);
    _remoteIceBySession.remove(sessionId);
    _localOfferBySession.remove(sessionId);
  }

  void clearAll() {
    _remoteAnswerBySession.clear();
    _remoteIceBySession.clear();
    _localOfferBySession.clear();
  }
}
