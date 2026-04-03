class SyncSignalingMessages {
  // Browser/phone session auth and sync frames.
  static const auth = 'AUTH';
  static const sessionAuth = 'SESSION_AUTH';
  static const authBegin = 'AUTH_BEGIN';
  static const authOk = 'AUTH_OK';
  static const authChallenge = 'AUTH_CHALLENGE';
  static const authFail = 'AUTH_FAIL';
  static const ping = 'PING';
  static const pong = 'PONG';
  static const pull = 'PULL';
  static const rows = 'ROWS';
  static const write = 'WRITE';
  static const writeOk = 'WRITE_OK';
  static const push = 'PUSH';
  static const syncPlan = 'SYNC_PLAN';

  // WebRTC signaling scaffolding frames.
  static const signalOffer = 'SIGNAL_OFFER';
  static const signalAnswer = 'SIGNAL_ANSWER';
  static const signalIceCandidate = 'SIGNAL_ICE_CANDIDATE';
  static const signalAck = 'SIGNAL_ACK';
  static const signalError = 'SIGNAL_ERROR';
  static const signalUnsupported = 'SIGNAL_UNSUPPORTED';
  static const webRtcRuntime = 'WEBRTC_RUNTIME';

  static bool isWebRtcSignalType(String type) {
    switch (type) {
      case signalOffer:
      case signalAnswer:
      case signalIceCandidate:
        return true;
      default:
        return false;
    }
  }

  static bool requiresSdp(String type) {
    return type == signalOffer || type == signalAnswer;
  }

  static bool requiresCandidate(String type) {
    return type == signalIceCandidate;
  }
}
