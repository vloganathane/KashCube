import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum WebRtcPeerRuntimeEventType {
  peerSessionCreated,
  dataChannelReady,
  peerSessionClosed,
}

class WebRtcPeerRuntimeEvent {
  const WebRtcPeerRuntimeEvent({
    required this.sessionId,
    required this.type,
  });

  final String sessionId;
  final WebRtcPeerRuntimeEventType type;

  String get typeName {
    switch (type) {
      case WebRtcPeerRuntimeEventType.peerSessionCreated:
        return 'PEER_SESSION_CREATED';
      case WebRtcPeerRuntimeEventType.dataChannelReady:
        return 'DATA_CHANNEL_READY';
      case WebRtcPeerRuntimeEventType.peerSessionClosed:
        return 'PEER_SESSION_CLOSED';
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'session_id': sessionId,
      'event': typeName,
    };
  }
}

abstract class WebRtcPeerOps {
  Stream<WebRtcPeerRuntimeEvent> get runtimeEvents;

  Future<void> createPeerSession();

  Future<void> setLocalOfferSdp(String sdp);

  Future<void> setRemoteAnswerSdp(String sdp);

  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate);

  Future<void> ensureDataChannel();

  Future<void> closePeerSession();
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
  Stream<WebRtcPeerRuntimeEvent> get runtimeEvents =>
      const Stream<WebRtcPeerRuntimeEvent>.empty();

  @override
  Future<void> createPeerSession() async {}

  @override
  Future<void> setLocalOfferSdp(String sdp) async {}

  @override
  Future<void> setRemoteAnswerSdp(String sdp) async {}

  @override
  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) async {}

  @override
  Future<void> ensureDataChannel() async {}

  @override
  Future<void> closePeerSession() async {}
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
  final StreamController<WebRtcPeerRuntimeEvent> _runtimeEventsController =
      StreamController<WebRtcPeerRuntimeEvent>.broadcast();
  bool dataChannelEnsured = false;
  bool sessionCreated = false;
  bool sessionClosed = false;

  @override
  Stream<WebRtcPeerRuntimeEvent> get runtimeEvents =>
      _runtimeEventsController.stream;

  @override
  Future<void> createPeerSession() async {
    sessionCreated = true;
    operationLog.add('createPeerSession');
    _runtimeEventsController.add(
      WebRtcPeerRuntimeEvent(
        sessionId: sessionId,
        type: WebRtcPeerRuntimeEventType.peerSessionCreated,
      ),
    );
  }

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
    _runtimeEventsController.add(
      WebRtcPeerRuntimeEvent(
        sessionId: sessionId,
        type: WebRtcPeerRuntimeEventType.dataChannelReady,
      ),
    );
  }

  @override
  Future<void> closePeerSession() async {
    sessionClosed = true;
    operationLog.add('closePeerSession');
    _runtimeEventsController.add(
      WebRtcPeerRuntimeEvent(
        sessionId: sessionId,
        type: WebRtcPeerRuntimeEventType.peerSessionClosed,
      ),
    );
    await _runtimeEventsController.close();
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
  }) : _channel = channel ?? _sharedChannel {
    _runtimeEventControllers[sessionId] = _runtimeEventsController;
    _ensureMethodCallHandler();
  }

  static const String _defaultChannelName = 'kashcube/webrtc_peer_ops';
  static const String _runtimeEventMethod = 'onRuntimeEvent';
  static final MethodChannel _sharedChannel =
      const MethodChannel(_defaultChannelName);
  static final Map<String, StreamController<WebRtcPeerRuntimeEvent>>
      _runtimeEventControllers =
      <String, StreamController<WebRtcPeerRuntimeEvent>>{};
  static bool _methodCallHandlerInstalled = false;

  final String sessionId;
  final MethodChannel _channel;
  final StreamController<WebRtcPeerRuntimeEvent> _runtimeEventsController =
      StreamController<WebRtcPeerRuntimeEvent>.broadcast();

  @override
  Stream<WebRtcPeerRuntimeEvent> get runtimeEvents =>
      _runtimeEventsController.stream;

  static void _ensureMethodCallHandler() {
    if (_methodCallHandlerInstalled) {
      return;
    }
    _methodCallHandlerInstalled = true;
    _sharedChannel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != _runtimeEventMethod) {
      return;
    }

    final args = call.arguments;
    if (args is! Map) {
      return;
    }
    _dispatchRuntimeEvent(Map<String, dynamic>.from(args));
  }

  static void _dispatchRuntimeEvent(Map<String, dynamic> payload) {
    final sessionId = payload['session_id']?.toString();
    final eventName = payload['event']?.toString();
    if (sessionId == null || sessionId.isEmpty || eventName == null) {
      return;
    }

    final controller = _runtimeEventControllers[sessionId];
    if (controller == null || controller.isClosed) {
      return;
    }

    final eventType = _parseRuntimeEventType(eventName);
    if (eventType == null) {
      return;
    }

    controller.add(
      WebRtcPeerRuntimeEvent(sessionId: sessionId, type: eventType),
    );

    if (eventType == WebRtcPeerRuntimeEventType.peerSessionClosed) {
      _runtimeEventControllers.remove(sessionId);
      unawaited(controller.close());
    }
  }

  static WebRtcPeerRuntimeEventType? _parseRuntimeEventType(String raw) {
    switch (raw) {
      case 'PEER_SESSION_CREATED':
        return WebRtcPeerRuntimeEventType.peerSessionCreated;
      case 'DATA_CHANNEL_READY':
        return WebRtcPeerRuntimeEventType.dataChannelReady;
      case 'PEER_SESSION_CLOSED':
        return WebRtcPeerRuntimeEventType.peerSessionClosed;
      default:
        return null;
    }
  }

  @visibleForTesting
  static void dispatchRuntimeEventForTest(Map<String, dynamic> payload) {
    _dispatchRuntimeEvent(payload);
  }

  @override
  Future<void> createPeerSession() async {
    await _invoke('createPeerSession', const <String, dynamic>{});
  }

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
  Future<void> ensureDataChannel() async {
    await _invoke('ensureDataChannel', const <String, dynamic>{});
  }

  @override
  Future<void> closePeerSession() async {
    await _invoke('closePeerSession', const <String, dynamic>{});
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
