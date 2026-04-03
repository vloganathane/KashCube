import 'dart:async';

import 'webrtc_sync_transport_channel.dart';

/// Concrete bridge shell for future flutter_webrtc DataChannel wiring.
///
/// This class owns session-scoped negotiation artifacts and frame buffers,
/// while remaining transport-only (no direct RTCPeerConnection dependency yet).
class WebRtcDataChannelBridgeShell implements WebRtcNegotiationAwareBridge {
  WebRtcDataChannelBridgeShell({required this.sessionId});

  final String sessionId;

  final StreamController<String> _inbound = StreamController<String>.broadcast();
  final List<String> _outboundFrames = <String>[];
  final List<Map<String, dynamic>> _remoteIceCandidates =
      <Map<String, dynamic>>[];

  String? _localOfferSdp;
  String? _remoteAnswerSdp;
  bool _closed = false;

  bool get isClosed => _closed;
  String? get localOfferSdp => _localOfferSdp;
  String? get remoteAnswerSdp => _remoteAnswerSdp;
  List<String> get outboundFrames => List<String>.unmodifiable(_outboundFrames);
  List<Map<String, dynamic>> get remoteIceCandidates =>
      List<Map<String, dynamic>>.unmodifiable(_remoteIceCandidates);

  @override
  void applyLocalOfferSdp(String sdp) {
    if (_closed || sdp.isEmpty) return;
    _localOfferSdp = sdp;
  }

  @override
  void applyRemoteAnswerSdp(String sdp) {
    if (_closed || sdp.isEmpty) return;
    _remoteAnswerSdp = sdp;
  }

  @override
  void addRemoteIceCandidate(Map<String, dynamic> candidate) {
    if (_closed || candidate.isEmpty) return;
    _remoteIceCandidates.add(Map<String, dynamic>.from(candidate));
  }

  /// Test/runtime hook to inject inbound frame from DataChannel callback.
  void emitInboundFrame(String frame) {
    if (_closed || frame.isEmpty) return;
    _inbound.add(frame);
  }

  @override
  Stream<String> get inboundFrames => _inbound.stream;

  @override
  Future<void> sendFrame(String jsonFrame) async {
    if (_closed) {
      throw StateError('WebRTC bridge is closed for session $sessionId');
    }
    _outboundFrames.add(jsonFrame);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _inbound.close();
  }
}
