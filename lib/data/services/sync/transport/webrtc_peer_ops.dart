abstract class WebRtcPeerOps {
  Future<void> setLocalOfferSdp(String sdp);

  Future<void> setRemoteAnswerSdp(String sdp);

  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate);

  Future<void> ensureDataChannel();
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
