import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/sync_signaling_messages.dart';
import 'package:kash_cube/data/services/sync/transport/webrtc_data_channel_bridge_shell.dart';
import 'package:kash_cube/data/services/sync/transport/webrtc_peer_ops.dart';
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

class _FakeWebRtcPeerOps implements WebRtcPeerOps {
  _FakeWebRtcPeerOps({this.sessionId = 'fake'});

  final String sessionId;
  String? localOfferSdp;
  String? remoteAnswerSdp;
  final List<Map<String, dynamic>> remoteIceCandidates =
      <Map<String, dynamic>>[];
  final StreamController<WebRtcPeerRuntimeEvent> _events =
      StreamController<WebRtcPeerRuntimeEvent>.broadcast();
  final StreamController<String> _payloadFrames =
      StreamController<String>.broadcast();
  final List<String> sentDataChannelFrames = <String>[];
  int ensureDataChannelCount = 0;
  int createPeerSessionCount = 0;
  int closePeerSessionCount = 0;

  @override
  Stream<WebRtcPeerRuntimeEvent> get runtimeEvents => _events.stream;

  @override
  Stream<String> get payloadFrames => _payloadFrames.stream;

  @override
  Future<void> createPeerSession() async {
    createPeerSessionCount += 1;
    _events.add(
      WebRtcPeerRuntimeEvent(
        sessionId: sessionId,
        type: WebRtcPeerRuntimeEventType.peerSessionCreated,
      ),
    );
  }

  @override
  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) async {
    remoteIceCandidates.add(Map<String, dynamic>.from(candidate));
  }

  @override
  Future<void> ensureDataChannel() async {
    ensureDataChannelCount += 1;
  }

  @override
  Future<void> sendDataChannelFrame(String frame) async {
    sentDataChannelFrames.add(frame);
  }

  @override
  Future<void> closePeerSession() async {
    closePeerSessionCount += 1;
    _events.add(
      WebRtcPeerRuntimeEvent(
        sessionId: sessionId,
        type: WebRtcPeerRuntimeEventType.peerSessionClosed,
      ),
    );
    await _payloadFrames.close();
    await _events.close();
  }

  @override
  Future<void> setLocalOfferSdp(String sdp) async {
    localOfferSdp = sdp;
  }

  @override
  Future<void> setRemoteAnswerSdp(String sdp) async {
    remoteAnswerSdp = sdp;
  }

  void emitInboundPayloadFrame(String frame) {
    _payloadFrames.add(frame);
  }

  void emitReadyEvent() {
    _events.add(
      WebRtcPeerRuntimeEvent(
        sessionId: sessionId,
        type: WebRtcPeerRuntimeEventType.dataChannelReady,
      ),
    );
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

    test('runtime sync propagates offer/answer/ICE into negotiation-aware bridge', () async {
      final channel = WebRtcSyncTransportChannel();
      final mailbox = channel.mailbox;
      const sessionId = 'sess-005';
      final bridge = WebRtcDataChannelBridgeShell(sessionId: sessionId);

      channel.registerDataChannelBridge(sessionId: sessionId, bridge: bridge);

      mailbox.stageLocalOffer(sessionId: sessionId, offerSdp: 'offer-from-mailbox');
      mailbox.ingestSignalingFrame({
        'type': SyncSignalingMessages.signalAnswer,
        'session_id': sessionId,
        'sdp': 'answer-from-mailbox',
      });
      mailbox.ingestSignalingFrame({
        'type': SyncSignalingMessages.signalIceCandidate,
        'session_id': sessionId,
        'candidate': {'candidate': 'ice-mailbox-1'},
      });

      channel.syncRuntimeFromMailbox(sessionId: sessionId);

      expect(bridge.localOfferSdp, 'offer-from-mailbox');
      expect(bridge.remoteAnswerSdp, 'answer-from-mailbox');
      expect(bridge.remoteIceCandidates, hasLength(1));

      await channel.unregisterDataChannelBridge(sessionId);
      await channel.close();
    });

    test('bridge shell syncs buffered artifacts into attached peer ops', () async {
      final bridge = WebRtcDataChannelBridgeShell(sessionId: 'sess-006')
        ..applyLocalOfferSdp('offer-buffered')
        ..applyRemoteAnswerSdp('answer-buffered')
        ..addRemoteIceCandidate({'candidate': 'ice-buffered'});
      final peerOps = _FakeWebRtcPeerOps(sessionId: 'sess-006');
      await bridge.sendFrame('{"type":"SYNC","table":"transactions"}');

      await bridge.attachPeerOps(peerOps);

      expect(peerOps.localOfferSdp, 'offer-buffered');
      expect(peerOps.remoteAnswerSdp, 'answer-buffered');
      expect(peerOps.remoteIceCandidates, hasLength(1));
      expect(peerOps.ensureDataChannelCount, 1);
      expect(peerOps.createPeerSessionCount, 1);
      expect(bridge.isDataChannelReady, isFalse);
      expect(peerOps.sentDataChannelFrames, isEmpty);

      peerOps.emitReadyEvent();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridge.isDataChannelReady, isTrue);
      expect(peerOps.sentDataChannelFrames, ['{"type":"SYNC","table":"transactions"}']);

      await bridge.close();
      expect(peerOps.closePeerSessionCount, 1);
    });

    test('bridge shell deduplicates ICE before forwarding to peer ops', () async {
      final bridge = WebRtcDataChannelBridgeShell(sessionId: 'sess-007');
      final peerOps = _FakeWebRtcPeerOps(sessionId: 'sess-007');

      await bridge.attachPeerOps(peerOps);
      bridge.addRemoteIceCandidate({'candidate': 'ice-dup'});
      bridge.addRemoteIceCandidate({'candidate': 'ice-dup'});

      expect(bridge.remoteIceCandidates, hasLength(1));
      expect(peerOps.remoteIceCandidates, hasLength(1));
    });

    test('bridge forwards inbound payload frames from peer ops', () async {
      final bridge = WebRtcDataChannelBridgeShell(sessionId: 'sess-007b');
      final peerOps = _FakeWebRtcPeerOps(sessionId: 'sess-007b');

      await bridge.attachPeerOps(peerOps);
      peerOps.emitInboundPayloadFrame('{"type":"ROWS","table":"transactions"}');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Payload frames are ignored until the data channel is reported ready.
      final gatedFuture = bridge.inboundFrames.timeout(
        const Duration(milliseconds: 20),
        onTimeout: (sink) => sink.close(),
      ).toList();
      expect(await gatedFuture, isEmpty);

      final inboundFuture = bridge.inboundFrames.firstWhere(
        (frame) => !frame.contains('"type":"${SyncSignalingMessages.webRtcRuntime}"'),
      );
      peerOps.emitReadyEvent();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      peerOps.emitInboundPayloadFrame('{"type":"ROWS","table":"transactions"}');

      expect(
        await inboundFuture,
        '{"type":"ROWS","table":"transactions"}',
      );

      await bridge.close();
    });

    test('registering bridge shell auto-attaches default peer ops', () async {
      final channel = WebRtcSyncTransportChannel();
      final bridge = WebRtcDataChannelBridgeShell(sessionId: 'sess-008');

      expect(bridge.hasPeerOps, isFalse);

      channel.registerDataChannelBridge(sessionId: 'sess-008', bridge: bridge);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridge.hasPeerOps, isTrue);

      await channel.unregisterDataChannelBridge('sess-008');
      await channel.close();
    });

    test('custom peer ops factory can attach flutter_webrtc shell placeholder', () async {
      FlutterWebRtcPeerOpsShell? createdPeerOps;
      final channel = WebRtcSyncTransportChannel(
        peerOpsFactory: (sessionId) {
          createdPeerOps = FlutterWebRtcPeerOpsShell(sessionId: sessionId);
          return createdPeerOps!;
        },
      );
      final bridge = WebRtcDataChannelBridgeShell(sessionId: 'sess-009');

      channel.registerDataChannelBridge(sessionId: 'sess-009', bridge: bridge);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridge.hasPeerOps, isTrue);
      expect(createdPeerOps, isNotNull);
      expect(createdPeerOps!.sessionId, 'sess-009');

      bridge.applyLocalOfferSdp('offer-custom');
      bridge.applyRemoteAnswerSdp('answer-custom');
      bridge.addRemoteIceCandidate({'candidate': 'ice-custom'});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(createdPeerOps!.localOfferSdp, 'offer-custom');
      expect(createdPeerOps!.remoteAnswerSdp, 'answer-custom');
      expect(createdPeerOps!.remoteIceCandidates, hasLength(1));
      expect(createdPeerOps!.dataChannelEnsured, isTrue);

      await channel.unregisterDataChannelBridge('sess-009');
      await channel.close();
    });

  });
}
