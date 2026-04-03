import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_transport_channel.dart';

class _FakeCloudSignalingAdapter implements CloudSignalingAdapter {
  final StreamController<Map<String, dynamic>> _inboundController =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sentFrames = <Map<String, dynamic>>[];
  Uri? connectedUri;
  int closeCount = 0;

  @override
  Stream<Map<String, dynamic>> get inboundFrames => _inboundController.stream;

  @override
  Future<void> connect(Uri uri) async {
    connectedUri = uri;
  }

  @override
  Future<void> sendFrame(Map<String, dynamic> payload) async {
    sentFrames.add(Map<String, dynamic>.from(payload));
  }

  void emitInbound(Map<String, dynamic> frame) {
    _inboundController.add(Map<String, dynamic>.from(frame));
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    await _inboundController.close();
  }
}

void main() {
  group('CloudSignalingTransportChannel', () {
    test('bridges inbound adapter frames to transport stream as JSON', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));
      adapter.emitInbound(<String, dynamic>{'type': 'SIGNAL_ACK', 'ok': true});

      await expectLater(
        channel.stream,
        emits('{"type":"SIGNAL_ACK","ok":true}'),
      );

      expect(adapter.connectedUri.toString(), 'wss://example.invalid/signal');
      await channel.close();
      expect(adapter.closeCount, 1);
    });

    test('forwards outbound payloads to adapter sendFrame', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));
      channel.sendJson(<String, dynamic>{'type': 'SIGNAL_OFFER', 'sdp': 'offer'});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(adapter.sentFrames, hasLength(1));
      expect(adapter.sentFrames.first['type'], 'SIGNAL_OFFER');
      expect(adapter.sentFrames.first['sdp'], 'offer');

      await channel.close();
    });
  });
}
