import 'dart:async';
import 'dart:convert';

import 'cloud_signaling_frame_mapper.dart';
import 'sync_transport_channel.dart';

typedef CloudSignalingAdapterFactory = CloudSignalingAdapter Function();

enum CloudTurnRelayMode {
  disabled,
  preferred,
  required,
}

class CloudSignalingSessionOptions {
  const CloudSignalingSessionOptions({
    this.turnRelayMode = CloudTurnRelayMode.disabled,
    this.relayServerHints = const <String>[],
  });

  final CloudTurnRelayMode turnRelayMode;
  final List<String> relayServerHints;
}

abstract class CloudSignalingAdapter {
  Stream<Map<String, dynamic>> get inboundFrames;

  Future<void> connect(
    Uri uri, {
    CloudSignalingSessionOptions options = const CloudSignalingSessionOptions(),
  });

  Future<void> sendFrame(Map<String, dynamic> payload);

  Future<void> close();
}

class CloudSignalingUnavailableAdapter implements CloudSignalingAdapter {
  static const unsupportedReason =
      'Cloud signaling is not available in this local-first build';

  @override
  Stream<Map<String, dynamic>> get inboundFrames =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> connect(
    Uri uri, {
    CloudSignalingSessionOptions options = const CloudSignalingSessionOptions(),
  }) async {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<void> sendFrame(Map<String, dynamic> payload) async {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<void> close() async {}
}

/// Placeholder channel for future cloud signaling.
///
/// This intentionally fails closed in the local-first build so cloud signaling
/// can be feature-flagged and exercised without introducing network behavior.
class CloudSignalingTransportChannel implements SyncTransportChannel {
  CloudSignalingTransportChannel({
    CloudSignalingAdapterFactory? adapterFactory,
    this.sessionOptions = const CloudSignalingSessionOptions(),
    CloudSignalingFrameMapper? frameMapper,
  })  : _adapter =
            (adapterFactory ?? () => CloudSignalingUnavailableAdapter())(),
        _mapper = frameMapper ?? const CloudSignalingFrameMapper();

  final CloudSignalingAdapter _adapter;
  final CloudSignalingSessionOptions sessionOptions;
  final CloudSignalingFrameMapper _mapper;
  final StreamController<dynamic> _inboundController =
      StreamController<dynamic>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _inboundSub;

  @override
  Future<void> connect(Uri uri) async {
    await _adapter.connect(uri, options: sessionOptions);
    await _inboundSub?.cancel();
    _inboundSub = _adapter.inboundFrames.listen((frame) {
      final mapped = _mapper.mapInbound(frame);
      if (mapped != null) {
        _inboundController.add(jsonEncode(mapped));
      }
    });
  }

  @override
  Stream<dynamic> get stream => _inboundController.stream;

  @override
  void sendJson(Map<String, dynamic> payload) {
    final mapped = _mapper.mapOutbound(payload);
    unawaited(_adapter.sendFrame(mapped));
  }

  @override
  Future<void> close() async {
    await _inboundSub?.cancel();
    _inboundSub = null;
    await _adapter.close();
    await _inboundController.close();
  }
}
