import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  platformChannel,
}

WebRtcPeerOpsMode parseWebRtcPeerOpsMode(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'fluttershell':
    case 'flutter_shell':
      return WebRtcPeerOpsMode.flutterShell;
    case 'platformchannel':
    case 'platform_channel':
      return WebRtcPeerOpsMode.platformChannel;
    case 'noop':
    default:
      return WebRtcPeerOpsMode.noop;
  }
}

WebRtcPeerOpsFactory buildWebRtcPeerOpsFactory(WebRtcPeerOpsMode mode) {
  switch (mode) {
    case WebRtcPeerOpsMode.noop:
      return (_) => NoopWebRtcPeerOps();
    case WebRtcPeerOpsMode.flutterShell:
      return (sessionId) => FlutterWebRtcPeerOpsShell(sessionId: sessionId);
    case WebRtcPeerOpsMode.platformChannel:
      return (sessionId) => MethodChannelWebRtcPeerOps(sessionId: sessionId);
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

/// Platform channel backed peer ops implementation.
///
/// This is the production bridge point for native WebRTC plumbing while
/// preserving current fallback behavior: when no plugin handler is available,
/// calls are ignored with a debug log and do not throw.
class MethodChannelWebRtcPeerOps implements WebRtcPeerOps {
  MethodChannelWebRtcPeerOps({
    required this.sessionId,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_defaultChannelName);

  static const String _defaultChannelName = 'kashcube/webrtc_peer_ops';

  final String sessionId;
  final MethodChannel _channel;

  @override
  Future<void> setLocalOfferSdp(String sdp) {
    return _invoke('setLocalOfferSdp', {'sdp': sdp});
  }

  @override
  Future<void> setRemoteAnswerSdp(String sdp) {
    return _invoke('setRemoteAnswerSdp', {'sdp': sdp});
  }

  @override
  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) {
    return _invoke('addRemoteIceCandidate', {'candidate': candidate});
  }

  @override
  Future<void> ensureDataChannel() {
    return _invoke('ensureDataChannel', const <String, dynamic>{});
  }

  Future<void> _invoke(String method, Map<String, dynamic> payload) async {
    try {
      await _channel.invokeMethod<void>(
        method,
        <String, dynamic>{
          'session_id': sessionId,
          ...payload,
        },
      );
    } on MissingPluginException {
      debugPrint(
        '[MethodChannelWebRtcPeerOps] Missing plugin for $method '
        '(session=$sessionId)',
      );
    } on PlatformException catch (e) {
      debugPrint(
        '[MethodChannelWebRtcPeerOps] PlatformException during $method '
        '(session=$sessionId): ${e.code} ${e.message}',
      );
    }
  }
}
