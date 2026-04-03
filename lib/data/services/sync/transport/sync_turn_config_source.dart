import 'sync_transport_policy.dart';

/// Resolved TURN configuration for a cloud signaling session.
class SyncTurnConfig {
  const SyncTurnConfig({
    this.relayMode = SyncTurnRelayMode.disabled,
    this.relayServerHints = const <String>[],
  });

  final SyncTurnRelayMode relayMode;

  /// Ordered list of TURN server URIs to pass to the ICE agent.
  ///
  /// Format: `turn:<host>:<port>` or `turns:<host>:<port>`.
  /// Empty list allows the ICE agent to pick defaults.
  final List<String> relayServerHints;

  @override
  String toString() =>
      'SyncTurnConfig(relayMode: $relayMode, hints: $relayServerHints)';
}

/// Source of TURN configuration for cloud signaling sessions.
///
/// Implementations can back this with compile-time env flags, a local settings
/// store, or a test double. The provider calls [resolve] once per connect
/// attempt so stale values are never cached across reconnects.
abstract class SyncTurnConfigSource {
  const SyncTurnConfigSource();

  /// Returns the TURN config to use for the next cloud signaling session.
  SyncTurnConfig resolve();
}

/// Env-backed config source that reads [String.fromEnvironment] values at
/// resolve time.
///
/// This is the default source wired in production builds. Values are frozen at
/// compilation so they behave identically to the previous inline env lookup —
/// no behavioral change for builds that do not inject a custom source.
class EnvSyncTurnConfigSource extends SyncTurnConfigSource {
  const EnvSyncTurnConfigSource({
    this.relayModeKey = 'KASHCUBE_SYNC_TURN_RELAY_MODE',
    this.relayHintsKey = 'KASHCUBE_SYNC_TURN_RELAY_HINTS',
  });

  /// Dart `--dart-define` key for relay mode selection.
  final String relayModeKey;

  /// Dart `--dart-define` key for comma-separated relay server hints.
  ///
  /// Example: `turn:relay.example.invalid:3478,turns:relay.example.invalid:5349`
  final String relayHintsKey;

  @override
  SyncTurnConfig resolve() {
    return SyncTurnConfig(
      relayMode: _resolveMode(),
      relayServerHints: _resolveHints(),
    );
  }

  SyncTurnRelayMode _resolveMode() {
    // String.fromEnvironment values are compile-time constants so this cannot
    // actually vary at runtime, but expressing it as a method keeps the API
    // consistent with dynamic implementations.
    const raw = String.fromEnvironment(
      'KASHCUBE_SYNC_TURN_RELAY_MODE',
      defaultValue: 'disabled',
    );
    switch (raw.toLowerCase()) {
      case 'required':
      case 'turn_required':
        return SyncTurnRelayMode.required;
      case 'preferred':
      case 'turn_preferred':
      case 'prefer':
        return SyncTurnRelayMode.preferred;
      default:
        return SyncTurnRelayMode.disabled;
    }
  }

  List<String> _resolveHints() {
    const raw = String.fromEnvironment('KASHCUBE_SYNC_TURN_RELAY_HINTS');
    if (raw.isEmpty) return const <String>[];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}

/// Static config source for deterministic test control.
///
/// Pass this instead of [EnvSyncTurnConfigSource] in unit tests to avoid
/// relying on compile-time env values.
class StaticSyncTurnConfigSource extends SyncTurnConfigSource {
  const StaticSyncTurnConfigSource(this._config);

  final SyncTurnConfig _config;

  @override
  SyncTurnConfig resolve() => _config;
}
