import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/sync_signaling_messages.dart';
import 'package:kash_cube/data/services/sync/transport/webrtc_data_channel_bridge_shell.dart';
import 'package:kash_cube/data/services/sync/transport/webrtc_sync_transport_channel.dart';

class _FakeWebRtcBridge implements WebRtcDataChannelBridge {
  final StreamController<String> _inbound = StreamController<String>.broadcast();
  final List<String> sentFrames = <String>[];

  @override
  Stream<String> get inboundFrames => _inbound.stream;

  void pushInbound(String frame) {
    _inbound.add(frame);
  }

  @override
  Future<void> sendFrame(String jsonFrame) async {
    sentFrames.add(jsonFrame);
  }

  @override
  Future<void> close() async {
    await _inbound.close();
  }
}

void main() {
  setUp(() {
    // Mailbox is singleton-backed; clear before each test for isolation.
    WebRtcSyncTransportChannel().mailbox.clearAll();
  });

  group('WebRtcSyncTransportChannel mailbox/runtime bridge', () {
    test('syncRuntimeFromMailbox applies offer, answer, and ICE candidates', () {
      final channel = WebRtcSyncTransportChannel();
      final mailbox = channel.mailbox;
      const sessionId = 'sess-001';

      mailbox.stageLocalOffer(sessionId: sessionId, offerSdp: 'offer-sdp');
      mailbox.ingestSignalingFrame({
        'type': SyncSignalingMessages.signalAnswer,
        'session_id': sessionId,
        'sdp': 'answer-sdp',
      });
      mailbox.ingestSignalingFrame({
        'type': SyncSignalingMessages.signalIceCandidate,
        'session_id': sessionId,
        'candidate': {'candidate': 'ice-1'},
      });
      mailbox.ingestSignalingFrame({
        'type': SyncSignalingMessages.signalIceCandidate,
        'session_id': sessionId,
        'candidate': {'candidate': 'ice-2'},
      });

      final runtime = channel.syncRuntimeFromMailbox(sessionId: sessionId);

      expect(runtime.hasOffer, isTrue);
      expect(runtime.hasAnswer, isTrue);
      expect(runtime.remoteIceCount, 2);
      expect(runtime.localOfferSdp, 'offer-sdp');
      expect(runtime.remoteAnswerSdp, 'answer-sdp');
    });

    test('registered bridge routes inbound stream and outbound sendJson', () async {
      final channel = WebRtcSyncTransportChannel();
      final bridge = _FakeWebRtcBridge();
      const sessionId = 'sess-002';

      channel.registerDataChannelBridge(sessionId: sessionId, bridge: bridge);

      bridge.pushInbound('{"type":"PING"}');
      await expectLater(channel.stream, emits('{"type":"PING"}'));

      channel.sendJson({'type': 'PONG', 'ok': true});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridge.sentFrames, hasLength(1));
      final decoded = jsonDecode(bridge.sentFrames.first) as Map<String, dynamic>;
      expect(decoded['type'], 'PONG');
      expect(decoded['ok'], isTrue);

      await channel.unregisterDataChannelBridge(sessionId);
      await channel.close();
    });

    test('noop bridge supports lifecycle registration without throws', () async {
      final channel = WebRtcSyncTransportChannel();
      const sessionId = 'sess-003';

      channel.registerDataChannelBridge(
        sessionId: sessionId,
        bridge: NoopWebRtcDataChannelBridge(),
      );

      expect(() => channel.sendJson({'type': 'PING'}), returnsNormally);

      await channel.unregisterDataChannelBridge(sessionId);
      await channel.close();
    });

    test('bridge shell stores negotiation artifacts and routed outbound frame', () async {
      final channel = WebRtcSyncTransportChannel();
      const sessionId = 'sess-004';
      final bridge = WebRtcDataChannelBridgeShell(sessionId: sessionId)
        ..applyLocalOfferSdp('offer-sdp')
        ..applyRemoteAnswerSdp('answer-sdp')
        ..addRemoteIceCandidate({'candidate': 'ice-a'})
        ..addRemoteIceCandidate({'candidate': 'ice-b'});

      channel.registerDataChannelBridge(sessionId: sessionId, bridge: bridge);
      channel.sendJson({'type': 'SYNC', 'table': 'transactions'});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridge.localOfferSdp, 'offer-sdp');
      expect(bridge.remoteAnswerSdp, 'answer-sdp');
      expect(bridge.remoteIceCandidates.length, 2);
      expect(bridge.outboundFrames, hasLength(1));

      await channel.unregisterDataChannelBridge(sessionId);
      expect(bridge.isClosed, isTrue);
      await channel.close();
    });
  });
}
