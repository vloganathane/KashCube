abstract class WebRtcPeerOps {
  Future<void> setLocalOfferSdp(String sdp);

  Future<void> setRemoteAnswerSdp(String sdp);

  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate);

  Future<void> ensureDataChannel();
}

typedef WebRtcPeerOpsFactory = WebRtcPeerOps Function(String sessionId);

enum WebRtcPeerOpsMode {
  noop,
  flutterShell,
}

WebRtcPeerOpsFactory buildWebRtcPeerOpsFactory(WebRtcPeerOpsMode mode) {
  switch (mode) {
    case WebRtcPeerOpsMode.noop:
      return (_) => NoopWebRtcPeerOps();
    case WebRtcPeerOpsMode.flutterShell:
      return (sessionId) => FlutterWebRtcPeerOpsShell(sessionId: sessionId);
  }
}

class NoopWebRtcPeerOps implements WebRtcPeerOps {
  @override
  Future<void> setLocalOfferSdp(String sdp) async {}

  @override
  Future<void> setRemoteAnswerSdp(String sdp) async {}

  @override
  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) async {}

  @override
  Future<void> ensureDataChannel() async {}
}

/// Concrete placeholder for a future flutter_webrtc-backed peer implementation.
///
/// This shell records the operations that a real RTCPeerConnection wrapper
/// will perform once the plugin-backed implementation is wired in.
class FlutterWebRtcPeerOpsShell implements WebRtcPeerOps {
  FlutterWebRtcPeerOpsShell({required this.sessionId});

  final String sessionId;

  String? localOfferSdp;
  String? remoteAnswerSdp;
  final List<Map<String, dynamic>> remoteIceCandidates =
      <Map<String, dynamic>>[];
  final List<String> operationLog = <String>[];
  bool dataChannelEnsured = false;

  @override
  Future<void> setLocalOfferSdp(String sdp) async {
    localOfferSdp = sdp;
    operationLog.add('setLocalOfferSdp');
  }

  @override
  Future<void> setRemoteAnswerSdp(String sdp) async {
    remoteAnswerSdp = sdp;
    operationLog.add('setRemoteAnswerSdp');
  }

  @override
  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) async {
    remoteIceCandidates.add(Map<String, dynamic>.from(candidate));
    operationLog.add('addRemoteIceCandidate');
  }

  @override
  Future<void> ensureDataChannel() async {
    dataChannelEnsured = true;
    operationLog.add('ensureDataChannel');
  }
}
