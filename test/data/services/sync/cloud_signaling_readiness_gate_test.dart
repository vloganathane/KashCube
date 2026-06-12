import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_readiness_gate.dart';
import 'package:kash_cube/data/services/sync/transport/sync_transport_policy.dart';
import 'package:kash_cube/data/services/sync/transport/sync_turn_config_source.dart';

CloudSignalingReadinessGate _gate({
  SyncSignalingMode signalingMode = SyncSignalingMode.cloudRelay,
  bool adapterInjected = true,
  SyncTurnConfig turnConfig = const SyncTurnConfig(),
}) => CloudSignalingReadinessGate(
  signalingMode: signalingMode,
  adapterInjected: adapterInjected,
  turnConfigSource: StaticSyncTurnConfigSource(turnConfig),
);

void main() {
  group('CloudSignalingReadinessGate — ready', () {
    test(
      'returns CloudSignalingReady when all preconditions are satisfied',
      () {
        final result = _gate().check();
        expect(result, isA<CloudSignalingReady>());
      },
    );

    test('ready with TURN preferred and empty hints', () {
      final result = _gate(
        turnConfig: const SyncTurnConfig(
          relayMode: SyncTurnRelayMode.preferred,
          relayServerHints: <String>[],
        ),
      ).check();
      expect(result, isA<CloudSignalingReady>());
    });

    test('ready with TURN required and non-empty hints', () {
      final result = _gate(
        turnConfig: const SyncTurnConfig(
          relayMode: SyncTurnRelayMode.required,
          relayServerHints: <String>['turn:relay.example.invalid:3478'],
        ),
      ).check();
      expect(result, isA<CloudSignalingReady>());
    });
  });

  group('CloudSignalingReadinessGate — not ready', () {
    test('returns not-ready when cloud mode not selected', () {
      final result = _gate(signalingMode: SyncSignalingMode.localLan).check();
      expect(result, isA<CloudSignalingNotReady>());
      final notReady = result as CloudSignalingNotReady;
      expect(
        notReady.reasons,
        contains(CloudSignalingNotReadyReason.cloudModeNotSelected),
      );
    });

    test('returns not-ready when adapter is not injected', () {
      final result = _gate(adapterInjected: false).check();
      expect(result, isA<CloudSignalingNotReady>());
      final notReady = result as CloudSignalingNotReady;
      expect(
        notReady.reasons,
        contains(CloudSignalingNotReadyReason.noAdapterInjected),
      );
    });

    test('returns not-ready when TURN required but no hints provided', () {
      final result = _gate(
        turnConfig: const SyncTurnConfig(
          relayMode: SyncTurnRelayMode.required,
          relayServerHints: <String>[],
        ),
      ).check();
      expect(result, isA<CloudSignalingNotReady>());
      final notReady = result as CloudSignalingNotReady;
      expect(
        notReady.reasons,
        contains(CloudSignalingNotReadyReason.turnRequiredButNoHints),
      );
    });

    test('accumulates multiple reasons', () {
      final result = _gate(
        signalingMode: SyncSignalingMode.localLan,
        adapterInjected: false,
        turnConfig: const SyncTurnConfig(
          relayMode: SyncTurnRelayMode.required,
          relayServerHints: <String>[],
        ),
      ).check();
      expect(result, isA<CloudSignalingNotReady>());
      final notReady = result as CloudSignalingNotReady;
      expect(notReady.reasons, hasLength(3));
      expect(
        notReady.reasons,
        containsAll(<CloudSignalingNotReadyReason>[
          CloudSignalingNotReadyReason.cloudModeNotSelected,
          CloudSignalingNotReadyReason.noAdapterInjected,
          CloudSignalingNotReadyReason.turnRequiredButNoHints,
        ]),
      );
    });

    test('TURN disabled with empty hints is not a failure', () {
      final result = _gate(
        turnConfig: const SyncTurnConfig(
          relayMode: SyncTurnRelayMode.disabled,
          relayServerHints: <String>[],
        ),
      ).check();
      expect(result, isA<CloudSignalingReady>());
    });
  });

  group('CloudSignalingReadinessResult sealed type exhaustion', () {
    test(
      'CloudSignalingReady is distinguishable from CloudSignalingNotReady',
      () {
        final ready = _gate().check();
        final notReady = _gate(adapterInjected: false).check();
        expect(ready is CloudSignalingReady, isTrue);
        expect(notReady is CloudSignalingNotReady, isTrue);
        expect(ready is CloudSignalingNotReady, isFalse);
        expect(notReady is CloudSignalingReady, isFalse);
      },
    );
  });
}
