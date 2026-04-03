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

      await ops.setLocalOfferSdp('offer-sdp');
      await ops.setRemoteAnswerSdp('answer-sdp');
      await ops.addRemoteIceCandidate({'candidate': 'ice-1'});
      await ops.ensureDataChannel();

      expect(calls.map((c) => c.method), <String>[
        'setLocalOfferSdp',
        'setRemoteAnswerSdp',
        'addRemoteIceCandidate',
        'ensureDataChannel',
      ]);

      final firstArgs = Map<String, dynamic>.from(calls.first.arguments as Map);
      expect(firstArgs['session_id'], 'sess-101');
      expect(firstArgs['sdp'], 'offer-sdp');

      final thirdArgs = Map<String, dynamic>.from(calls[2].arguments as Map);
      expect(thirdArgs['session_id'], 'sess-101');
      expect(
        Map<String, dynamic>.from(thirdArgs['candidate'] as Map)['candidate'],
        'ice-1',
      );
    });
  });
}
