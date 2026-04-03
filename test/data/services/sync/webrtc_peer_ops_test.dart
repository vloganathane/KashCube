import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/webrtc_peer_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRtcPeerOps mode parsing', () {
    test('defaults to noop for null/unknown', () {
      expect(parseWebRtcPeerOpsMode(null), WebRtcPeerOpsMode.noop);
      expect(parseWebRtcPeerOpsMode('unknown'), WebRtcPeerOpsMode.noop);
    });

    test('parses flutter shell aliases', () {
      expect(
        parseWebRtcPeerOpsMode('flutter_shell'),
        WebRtcPeerOpsMode.flutterShell,
      );
      expect(
        parseWebRtcPeerOpsMode('fluttershell'),
        WebRtcPeerOpsMode.flutterShell,
      );
    });

    test('parses platform channel aliases', () {
      expect(
        parseWebRtcPeerOpsMode('platform_channel'),
        WebRtcPeerOpsMode.platformChannel,
      );
      expect(
        parseWebRtcPeerOpsMode('platformchannel'),
        WebRtcPeerOpsMode.platformChannel,
      );
    });
  });

  group('MethodChannelWebRtcPeerOps', () {
    const channelName = 'kashcube/webrtc_peer_ops';
    const channel = MethodChannel(channelName);
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('invokes expected methods with session-scoped payload', () async {
      final ops = MethodChannelWebRtcPeerOps(
        sessionId: 'sess-101',
        channel: channel,
      );
      final eventsFuture = ops.runtimeEvents.take(3).toList();

      await ops.createPeerSession();
      await ops.setLocalOfferSdp('offer-sdp');
      await ops.setRemoteAnswerSdp('answer-sdp');
      await ops.addRemoteIceCandidate({'candidate': 'ice-1'});
      await ops.ensureDataChannel();
      MethodChannelWebRtcPeerOps.dispatchRuntimeEventForTest({
        'session_id': 'sess-101',
        'event': 'PEER_SESSION_CREATED',
      });
      MethodChannelWebRtcPeerOps.dispatchRuntimeEventForTest({
        'session_id': 'sess-101',
        'event': 'DATA_CHANNEL_READY',
      });
      await ops.closePeerSession();
      MethodChannelWebRtcPeerOps.dispatchRuntimeEventForTest({
        'session_id': 'sess-101',
        'event': 'PEER_SESSION_CLOSED',
      });

      final events = await eventsFuture;

      expect(calls.map((c) => c.method), <String>[
        'createPeerSession',
        'setLocalOfferSdp',
        'setRemoteAnswerSdp',
        'addRemoteIceCandidate',
        'ensureDataChannel',
        'closePeerSession',
      ]);

      final secondArgs = Map<String, dynamic>.from(calls[1].arguments as Map);
      expect(secondArgs['session_id'], 'sess-101');
      expect(secondArgs['sdp'], 'offer-sdp');

      final fourthArgs = Map<String, dynamic>.from(calls[3].arguments as Map);
      expect(fourthArgs['session_id'], 'sess-101');
      expect(
        Map<String, dynamic>.from(fourthArgs['candidate'] as Map)['candidate'],
        'ice-1',
      );

      expect(
        events.map((e) => e.type),
        <WebRtcPeerRuntimeEventType>[
          WebRtcPeerRuntimeEventType.peerSessionCreated,
          WebRtcPeerRuntimeEventType.dataChannelReady,
          WebRtcPeerRuntimeEventType.peerSessionClosed,
        ],
      );
    });
  });

  group('FlutterWebRtcPeerOpsShell runtime events', () {
    test('emits created, ready, and closed events', () async {
      final ops = FlutterWebRtcPeerOpsShell(sessionId: 'sess-shell');
      final eventsFuture = ops.runtimeEvents.take(3).toList();

      await ops.createPeerSession();
      await ops.ensureDataChannel();
      await ops.closePeerSession();

      final events = await eventsFuture;
      expect(
        events.map((e) => e.type),
        <WebRtcPeerRuntimeEventType>[
          WebRtcPeerRuntimeEventType.peerSessionCreated,
          WebRtcPeerRuntimeEventType.dataChannelReady,
          WebRtcPeerRuntimeEventType.peerSessionClosed,
        ],
      );
      expect(events.map((e) => e.sessionId).toSet(), {'sess-shell'});
    });
  });
}
