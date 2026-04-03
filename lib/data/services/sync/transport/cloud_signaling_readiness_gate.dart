import 'sync_transport_policy.dart';
import 'sync_turn_config_source.dart';

/// Reason why cloud signaling is not ready to activate.
enum CloudSignalingNotReadyReason {
  /// Cloud mode is not selected in the signaling policy.
  cloudModeNotSelected,

  /// A real cloud adapter factory has not been injected — the channel would
  /// fail closed via [CloudSignalingUnavailableAdapter].
  noAdapterInjected,

  /// TURN relay is set to [SyncTurnRelayMode.required] but no relay server
  /// hints have been provided. Without hints the ICE agent has no relay
  /// candidates and the session will fail under strict NAT.
  turnRequiredButNoHints,
}

/// Result of a cloud signaling readiness check.
sealed class CloudSignalingReadinessResult {
  const CloudSignalingReadinessResult();
}

/// Cloud signaling infrastructure is ready to attempt a connection.
final class CloudSignalingReady extends CloudSignalingReadinessResult {
  const CloudSignalingReady();
}

/// Cloud signaling infrastructure is not ready.
///
/// [reasons] is a non-empty list of the specific conditions that must be
/// resolved before cloud mode can be safely activated.
final class CloudSignalingNotReady extends CloudSignalingReadinessResult {
  const CloudSignalingNotReady(this.reasons)
      : assert(reasons.length > 0);

  final List<CloudSignalingNotReadyReason> reasons;
}

/// Evaluates whether the cloud signaling infrastructure is ready to activate.
///
/// The gate is called once per connect attempt before the cloud channel is
/// constructed. A [CloudSignalingNotReady] result causes the provider to fall
/// back to local signaling without attempting cloud connect, producing a
/// structured log instead of an exception.
///
/// Inject a custom instance in tests to drive specific ready/not-ready paths
/// without depending on compile-time env state.
class CloudSignalingReadinessGate {
  const CloudSignalingReadinessGate({
    required SyncSignalingMode signalingMode,
    required bool adapterInjected,
    required SyncTurnConfigSource turnConfigSource,
  })  : _signalingMode = signalingMode,
        _adapterInjected = adapterInjected,
        _turnConfigSource = turnConfigSource;

  final SyncSignalingMode _signalingMode;
  final bool _adapterInjected;
  final SyncTurnConfigSource _turnConfigSource;

  /// Checks all preconditions and returns a [CloudSignalingReadinessResult].
  CloudSignalingReadinessResult check() {
    final reasons = <CloudSignalingNotReadyReason>[];

    if (_signalingMode != SyncSignalingMode.cloudRelay) {
      reasons.add(CloudSignalingNotReadyReason.cloudModeNotSelected);
    }

    if (!_adapterInjected) {
      reasons.add(CloudSignalingNotReadyReason.noAdapterInjected);
    }

    final turnConfig = _turnConfigSource.resolve();
    if (turnConfig.relayMode == SyncTurnRelayMode.required &&
        turnConfig.relayServerHints.isEmpty) {
      reasons.add(CloudSignalingNotReadyReason.turnRequiredButNoHints);
    }

    if (reasons.isEmpty) return const CloudSignalingReady();
    return CloudSignalingNotReady(reasons);
  }
}
