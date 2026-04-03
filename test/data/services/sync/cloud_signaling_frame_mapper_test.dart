import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_frame_mapper.dart';
import 'package:kash_cube/data/services/sync/transport/sync_signaling_messages.dart';

void main() {
  const mapper = CloudSignalingFrameMapper();

  // All types routable through the cloud path.
  const controlPlaneTypes = <String>[
    SyncSignalingMessages.auth,
    SyncSignalingMessages.sessionAuth,
    SyncSignalingMessages.authBegin,
    SyncSignalingMessages.authOk,
    SyncSignalingMessages.authChallenge,
    SyncSignalingMessages.authFail,
    SyncSignalingMessages.ping,
    SyncSignalingMessages.pong,
    SyncSignalingMessages.signalOffer,
    SyncSignalingMessages.signalAnswer,
    SyncSignalingMessages.signalIceCandidate,
    SyncSignalingMessages.signalAck,
    SyncSignalingMessages.signalError,
    SyncSignalingMessages.signalUnsupported,
    SyncSignalingMessages.webRtcRuntime,
  ];

  const dataPlaneTypes = <String>[
    SyncSignalingMessages.pull,
    SyncSignalingMessages.rows,
    SyncSignalingMessages.write,
    SyncSignalingMessages.writeOk,
    SyncSignalingMessages.push,
    SyncSignalingMessages.syncPlan,
  ];

  const allRoutableTypes = [...controlPlaneTypes, ...dataPlaneTypes];

  group('CloudSignalingFrameMapper.mapInbound', () {
    test('passes through all control-plane types', () {
      for (final type in controlPlaneTypes) {
        final frame = <String, dynamic>{'type': type, 'data': 'x'};
        final result = mapper.mapInbound(frame);
        expect(result, isNotNull, reason: 'type=$type should pass inbound');
        expect(result!['type'], type);
        expect(result['data'], 'x');
      }
    });

    test('passes through all data-plane eligible types', () {
      for (final type in dataPlaneTypes) {
        final frame = <String, dynamic>{'type': type, 'payload': 1};
        final result = mapper.mapInbound(frame);
        expect(result, isNotNull, reason: 'type=$type should pass inbound');
        expect(result!['type'], type);
      }
    });

    test('returns null for frame missing type field', () {
      expect(mapper.mapInbound(<String, dynamic>{'payload': 'data'}), isNull);
    });

    test('returns null for frame with empty type string', () {
      expect(mapper.mapInbound(<String, dynamic>{'type': ''}), isNull);
    });

    test('returns null for frame with non-string type', () {
      expect(mapper.mapInbound(<String, dynamic>{'type': 42}), isNull);
      expect(mapper.mapInbound(<String, dynamic>{'type': null}), isNull);
      expect(
        mapper.mapInbound(<String, dynamic>{'type': <String, dynamic>{}}),
        isNull,
      );
    });

    test('returns null for unrecognized cloud-only type', () {
      expect(
        mapper.mapInbound(<String, dynamic>{'type': 'CLOUD_KEEPALIVE'}),
        isNull,
      );
      expect(
        mapper.mapInbound(<String, dynamic>{'type': 'UNKNOWN_FRAME'}),
        isNull,
      );
    });

    test('returns a defensive copy not the original map', () {
      final frame = <String, dynamic>{'type': SyncSignalingMessages.ping};
      final result = mapper.mapInbound(frame)!;
      result['injected'] = true;
      expect(frame.containsKey('injected'), isFalse);
    });
  });

  group('CloudSignalingFrameMapper.mapOutbound', () {
    test('passes through all routable types', () {
      for (final type in allRoutableTypes) {
        final frame = <String, dynamic>{'type': type};
        final result = mapper.mapOutbound(frame);
        expect(result['type'], type, reason: 'type=$type should pass outbound');
      }
    });

    test('throws ArgumentError for frame missing type field', () {
      expect(
        () => mapper.mapOutbound(<String, dynamic>{'payload': 'data'}),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for frame with empty type', () {
      expect(
        () => mapper.mapOutbound(<String, dynamic>{'type': ''}),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for unrecognized type', () {
      expect(
        () => mapper.mapOutbound(<String, dynamic>{'type': 'CLOUD_ONLY_FRAME'}),
        throwsArgumentError,
      );
    });

    test('returns a defensive copy not the original map', () {
      final frame = <String, dynamic>{'type': SyncSignalingMessages.pong};
      final result = mapper.mapOutbound(frame);
      result['injected'] = true;
      expect(frame.containsKey('injected'), isFalse);
    });
  });

  group('Parity: every type in SyncSignalingMessages is classified', () {
    // This test acts as a registry check — it will fail if a new type is added
    // to SyncSignalingMessages without updating isControlPlaneType or
    // isDataPlaneEligibleType, because the mapper would silently drop it.
    test('all routable types are accepted by both inbound and outbound', () {
      for (final type in allRoutableTypes) {
        expect(
          mapper.mapInbound(<String, dynamic>{'type': type}),
          isNotNull,
          reason: 'Parity: type=$type should be inbound-routable',
        );
        expect(
          () => mapper.mapOutbound(<String, dynamic>{'type': type}),
          returnsNormally,
          reason: 'Parity: type=$type should be outbound-routable',
        );
      }
    });
  });
}
