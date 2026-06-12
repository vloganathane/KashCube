import 'dart:async';
import 'dart:convert';

import 'sync_signaling_messages.dart';
import 'webrtc_peer_ops.dart';
import 'webrtc_sync_transport_channel.dart';

/// Concrete bridge shell for future flutter_webrtc DataChannel wiring.
///
/// This class owns session-scoped negotiation artifacts and frame buffers,
/// while remaining transport-only (no direct RTCPeerConnection dependency yet).
class WebRtcDataChannelBridgeShell implements WebRtcNegotiationAwareBridge {
  WebRtcDataChannelBridgeShell({required this.sessionId});

  final String sessionId;

  final StreamController<String> _inbound =
      StreamController<String>.broadcast();
  final List<String> _outboundFrames = <String>[];
  final List<Map<String, dynamic>> _remoteIceCandidates =
      <Map<String, dynamic>>[];
  final Set<String> _remoteIceCandidateKeys = <String>{};

  String? _localOfferSdp;
  String? _remoteAnswerSdp;
  WebRtcPeerOps? _peerOps;
  StreamSubscription<WebRtcPeerRuntimeEvent>? _peerRuntimeSub;
  StreamSubscription<String>? _peerPayloadSub;
  bool _dataChannelEnsured = false;
  bool _dataChannelReady = false;
  bool _closed = false;
  int _forwardedOutboundFrameCount = 0;

  bool get isClosed => _closed;
  bool get hasPeerOps => _peerOps != null;
  bool get isDataChannelReady => _dataChannelReady;
  String? get localOfferSdp => _localOfferSdp;
  String? get remoteAnswerSdp => _remoteAnswerSdp;
  List<String> get outboundFrames => List<String>.unmodifiable(_outboundFrames);
  List<Map<String, dynamic>> get remoteIceCandidates =>
      List<Map<String, dynamic>>.unmodifiable(_remoteIceCandidates);

  Future<void> attachPeerOps(WebRtcPeerOps peerOps) async {
    if (_closed) {
      throw StateError('WebRTC bridge is closed for session $sessionId');
    }

    await _peerRuntimeSub?.cancel();
    await _peerPayloadSub?.cancel();
    _peerRuntimeSub = peerOps.runtimeEvents.listen((event) {
      if (_closed || event.sessionId != sessionId) {
        return;
      }
      if (event.type == WebRtcPeerRuntimeEventType.dataChannelReady) {
        _dataChannelReady = true;
        unawaited(_flushBufferedFramesToPeerOps());
      } else if (event.type == WebRtcPeerRuntimeEventType.peerSessionClosed) {
        _dataChannelReady = false;
      }
      _inbound.add(
        jsonEncode({
          'type': SyncSignalingMessages.webRtcRuntime,
          ...event.toJson(),
        }),
      );
    });
    _peerPayloadSub = peerOps.payloadFrames.listen((frame) {
      if (_closed || !_dataChannelReady || frame.isEmpty) {
        return;
      }
      _inbound.add(frame);
    });

    _peerOps = peerOps;
    await _syncBufferedArtifactsToPeerOps();
  }

  Future<void> _syncBufferedArtifactsToPeerOps() async {
    final peerOps = _peerOps;
    if (peerOps == null) {
      return;
    }

    await peerOps.createPeerSession();

    if (_localOfferSdp != null && _localOfferSdp!.isNotEmpty) {
      await peerOps.setLocalOfferSdp(_localOfferSdp!);
    }
    if (_remoteAnswerSdp != null && _remoteAnswerSdp!.isNotEmpty) {
      await peerOps.setRemoteAnswerSdp(_remoteAnswerSdp!);
    }
    for (final candidate in _remoteIceCandidates) {
      await peerOps.addRemoteIceCandidate(candidate);
    }
    if (!_dataChannelEnsured) {
      _dataChannelEnsured = true;
      await peerOps.ensureDataChannel();
    }

    await _flushBufferedFramesToPeerOps();
  }

  Future<void> _flushBufferedFramesToPeerOps() async {
    final peerOps = _peerOps;
    if (peerOps == null || !_dataChannelReady) {
      return;
    }

    for (final frame in _outboundFrames.skip(_forwardedOutboundFrameCount)) {
      await peerOps.sendDataChannelFrame(frame);
      _forwardedOutboundFrameCount += 1;
    }
  }

  @override
  void applyLocalOfferSdp(String sdp) {
    if (_closed || sdp.isEmpty) return;
    _localOfferSdp = sdp;
    final peerOps = _peerOps;
    if (peerOps != null) {
      unawaited(peerOps.setLocalOfferSdp(sdp));
      if (!_dataChannelEnsured) {
        _dataChannelEnsured = true;
        unawaited(peerOps.ensureDataChannel());
      }
    }
  }

  @override
  void applyRemoteAnswerSdp(String sdp) {
    if (_closed || sdp.isEmpty) return;
    _remoteAnswerSdp = sdp;
    final peerOps = _peerOps;
    if (peerOps != null) {
      unawaited(peerOps.setRemoteAnswerSdp(sdp));
    }
  }

  @override
  void addRemoteIceCandidate(Map<String, dynamic> candidate) {
    if (_closed || candidate.isEmpty) return;
    final candidateKey = jsonEncode(candidate);
    if (!_remoteIceCandidateKeys.add(candidateKey)) {
      return;
    }
    _remoteIceCandidates.add(Map<String, dynamic>.from(candidate));
    final peerOps = _peerOps;
    if (peerOps != null) {
      unawaited(peerOps.addRemoteIceCandidate(candidate));
    }
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
    final peerOps = _peerOps;
    if (peerOps != null && _dataChannelReady) {
      await peerOps.sendDataChannelFrame(jsonFrame);
      _forwardedOutboundFrameCount += 1;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    await _peerRuntimeSub?.cancel();
    _peerRuntimeSub = null;
    await _peerPayloadSub?.cancel();
    _peerPayloadSub = null;

    final peerOps = _peerOps;
    _peerOps = null;
    if (peerOps != null) {
      await peerOps.closePeerSession();
    }
    _dataChannelReady = false;

    await _inbound.close();
  }
}
