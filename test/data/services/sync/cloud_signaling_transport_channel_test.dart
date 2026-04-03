import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_frame_mapper.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_transport_channel.dart';
import 'package:kash_cube/data/services/sync/transport/sync_frame_integrity_checker.dart';
import 'package:kash_cube/data/services/sync/transport/sync_signaling_messages.dart';

class _FakeCloudSignalingAdapter implements CloudSignalingAdapter {
  final StreamController<Map<String, dynamic>> _inboundController =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sentFrames = <Map<String, dynamic>>[];
  Uri? connectedUri;
  CloudSignalingSessionOptions? lastConnectOptions;
  int closeCount = 0;

  @override
  Stream<Map<String, dynamic>> get inboundFrames => _inboundController.stream;

  @override
  Future<void> connect(
    Uri uri, {
    CloudSignalingSessionOptions options = const CloudSignalingSessionOptions(),
  }) async {
    connectedUri = uri;
    lastConnectOptions = options;
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

    test('passes TURN relay options to adapter on connect', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
        sessionOptions: const CloudSignalingSessionOptions(
          turnRelayMode: CloudTurnRelayMode.required,
          relayServerHints: <String>['turn:relay.example.invalid:3478'],
        ),
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      expect(adapter.lastConnectOptions, isNotNull);
      expect(
        adapter.lastConnectOptions!.turnRelayMode,
        CloudTurnRelayMode.required,
      );
      expect(
        adapter.lastConnectOptions!.relayServerHints,
        <String>['turn:relay.example.invalid:3478'],
      );

      await channel.close();
    });
  });

  group('CloudSignalingTransportChannel frame mapper integration', () {
    test('drops inbound frames with unrecognized type', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      final received = <dynamic>[];
      channel.stream.listen(received.add);

      adapter.emitInbound(<String, dynamic>{'type': 'CLOUD_KEEPALIVE'});
      adapter.emitInbound(
        <String, dynamic>{'type': SyncSignalingMessages.ping},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Only the recognized PING frame should arrive.
      expect(received, hasLength(1));
      expect(received.first, contains('"type":"PING"'));

      await channel.close();
    });

    test('drops inbound frames missing type field', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      final received = <dynamic>[];
      channel.stream.listen(received.add);

      adapter.emitInbound(<String, dynamic>{'payload': 'no-type'});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, isEmpty);

      await channel.close();
    });

    test('sendJson validates outbound type via mapper', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      // Valid outbound frame should reach the adapter.
      channel.sendJson(
        <String, dynamic>{'type': SyncSignalingMessages.signalOffer, 'sdp': 'x'},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(adapter.sentFrames, hasLength(1));
      expect(adapter.sentFrames.first['type'], SyncSignalingMessages.signalOffer);

      await channel.close();
    });

    test('sendJson throws ArgumentError for unrecognized outbound type', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      expect(
        () => channel.sendJson(<String, dynamic>{'type': 'CLOUD_ONLY_FRAME'}),
        throwsArgumentError,
      );

      await channel.close();
    });

    test('accepts custom frameMapper injection', () async {
      var mapInboundCalled = 0;
      var mapOutboundCalled = 0;

      final customMapper = _CountingMapper(
        onMapInbound: () => mapInboundCalled += 1,
        onMapOutbound: () => mapOutboundCalled += 1,
      );

      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
        frameMapper: customMapper,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      adapter.emitInbound(
        <String, dynamic>{'type': SyncSignalingMessages.pong},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      channel.sendJson(<String, dynamic>{'type': SyncSignalingMessages.ping});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mapInboundCalled, 1);
      expect(mapOutboundCalled, 1);

      await channel.close();
    });
  });

  group('CloudSignalingTransportChannel integrity checker integration', () {
    test('passthrough checker (default) does not add _kash_sig on send', () async {
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      channel.sendJson(
        <String, dynamic>{
          'type': SyncSignalingMessages.write,
          'sync_id': 'pt-1',
          'table': 'transactions',
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(adapter.sentFrames, hasLength(1));
      expect(adapter.sentFrames.first.containsKey('_kash_sig'), isFalse);

      await channel.close();
    });

    test('HMAC checker adds _kash_sig to outbound data-plane frames', () async {
      final checker = HmacSyncFrameIntegrityChecker(
        secretBytes: utf8.encode('slice-33-test-secret'),
      );
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
        integrityChecker: checker,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      channel.sendJson(
        <String, dynamic>{
          'type': SyncSignalingMessages.write,
          'sync_id': 'hmac-out-1',
          'table': 'transactions',
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(adapter.sentFrames, hasLength(1));
      expect(adapter.sentFrames.first.containsKey('_kash_sig'), isTrue);

      await channel.close();
    });

    test('HMAC checker does not add _kash_sig to control-plane outbound frames', () async {
      final checker = HmacSyncFrameIntegrityChecker(
        secretBytes: utf8.encode('slice-33-test-secret'),
      );
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
        integrityChecker: checker,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      channel.sendJson(
        <String, dynamic>{'type': SyncSignalingMessages.signalOffer, 'sdp': 'offer'},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(adapter.sentFrames, hasLength(1));
      expect(adapter.sentFrames.first.containsKey('_kash_sig'), isFalse);

      await channel.close();
    });

    test('HMAC checker drops inbound data-plane frame with missing sig', () async {
      final checker = HmacSyncFrameIntegrityChecker(
        secretBytes: utf8.encode('slice-33-test-secret'),
      );
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
        integrityChecker: checker,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      final received = <dynamic>[];
      channel.stream.listen(received.add);

      // Unsigned data-plane frame — should be dropped by verify.
      adapter.emitInbound(<String, dynamic>{
        'type': SyncSignalingMessages.push,
        'table': 'transactions',
        'rows': <dynamic>[],
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, isEmpty);

      await channel.close();
    });

    test('HMAC checker passes inbound data-plane frame with valid sig', () async {
      final checker = HmacSyncFrameIntegrityChecker(
        secretBytes: utf8.encode('slice-33-test-secret'),
      );
      final adapter = _FakeCloudSignalingAdapter();
      final channel = CloudSignalingTransportChannel(
        adapterFactory: () => adapter,
        integrityChecker: checker,
      );

      await channel.connect(Uri.parse('wss://example.invalid/signal'));

      final received = <dynamic>[];
      channel.stream.listen(received.add);

      // Pre-sign the frame with the same checker before emitting inbound.
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.push,
        'table': 'transactions',
        'rows': <dynamic>[<String, dynamic>{'sync_id': 'r1'}],
      };
      final signed = checker.sign(frame);
      adapter.emitInbound(signed);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(1));
      // Delivered frame must not contain _kash_sig.
      final decoded = jsonDecode(received.first as String) as Map<String, dynamic>;
      expect(decoded.containsKey('_kash_sig'), isFalse);
      expect(decoded['type'], SyncSignalingMessages.push);

      await channel.close();
    });
  });
}

// Helper mapper that delegates to the real mapper but invokes callbacks for
// observability in the injection test.
class _CountingMapper extends CloudSignalingFrameMapper {
  _CountingMapper({
    required this.onMapInbound,
    required this.onMapOutbound,
  });

  final void Function() onMapInbound;
  final void Function() onMapOutbound;

  @override
  Map<String, dynamic>? mapInbound(Map<String, dynamic> cloudFrame) {
    onMapInbound();
    return super.mapInbound(cloudFrame);
  }

  @override
  Map<String, dynamic> mapOutbound(Map<String, dynamic> coordinatorFrame) {
    onMapOutbound();
    return super.mapOutbound(coordinatorFrame);
  }
}
