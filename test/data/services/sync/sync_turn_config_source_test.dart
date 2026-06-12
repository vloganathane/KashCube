import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/sync_transport_policy.dart';
import 'package:kash_cube/data/services/sync/transport/sync_turn_config_source.dart';

void main() {
  group('SyncTurnConfig', () {
    test('default config has disabled relay mode and empty hints', () {
      const config = SyncTurnConfig();
      expect(config.relayMode, SyncTurnRelayMode.disabled);
      expect(config.relayServerHints, isEmpty);
    });

    test('toString includes relayMode and hints', () {
      const config = SyncTurnConfig(
        relayMode: SyncTurnRelayMode.required,
        relayServerHints: <String>['turn:relay.example:3478'],
      );
      expect(config.toString(), contains('required'));
      expect(config.toString(), contains('relay.example'));
    });
  });

  group('StaticSyncTurnConfigSource', () {
    test('resolve returns the injected config unchanged', () {
      const config = SyncTurnConfig(
        relayMode: SyncTurnRelayMode.preferred,
        relayServerHints: <String>[
          'turn:a.example:3478',
          'turns:b.example:5349',
        ],
      );
      const source = StaticSyncTurnConfigSource(config);

      final resolved = source.resolve();
      expect(resolved.relayMode, SyncTurnRelayMode.preferred);
      expect(resolved.relayServerHints, <String>[
        'turn:a.example:3478',
        'turns:b.example:5349',
      ]);
    });

    test('resolve returns same instance on repeated calls', () {
      const config = SyncTurnConfig();
      const source = StaticSyncTurnConfigSource(config);

      expect(identical(source.resolve(), source.resolve()), isTrue);
    });
  });

  group('EnvSyncTurnConfigSource', () {
    // EnvSyncTurnConfigSource reads compile-time constants, so the resolved
    // values will always be the default ('disabled', empty hints) in the test
    // environment where no --dart-define flags are set.
    test('resolve returns disabled mode in test env (no dart-define)', () {
      const source = EnvSyncTurnConfigSource();
      final config = source.resolve();
      expect(config.relayMode, SyncTurnRelayMode.disabled);
    });

    test('resolve returns empty hints in test env (no dart-define)', () {
      const source = EnvSyncTurnConfigSource();
      final config = source.resolve();
      expect(config.relayServerHints, isEmpty);
    });

    test('resolve is idempotent across multiple calls', () {
      const source = EnvSyncTurnConfigSource();
      final first = source.resolve();
      final second = source.resolve();
      expect(first.relayMode, second.relayMode);
      expect(first.relayServerHints, second.relayServerHints);
    });
  });

  group('SyncTurnConfigSource polymorphism', () {
    test('StaticSyncTurnConfigSource satisfies abstract contract', () {
      const SyncTurnConfigSource source = StaticSyncTurnConfigSource(
        SyncTurnConfig(relayMode: SyncTurnRelayMode.required),
      );
      expect(source.resolve().relayMode, SyncTurnRelayMode.required);
    });

    test('EnvSyncTurnConfigSource satisfies abstract contract', () {
      const SyncTurnConfigSource source = EnvSyncTurnConfigSource();
      expect(source.resolve(), isA<SyncTurnConfig>());
    });
  });
}
