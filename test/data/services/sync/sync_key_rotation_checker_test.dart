import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/security/sync_key_rotation_checker.dart';
import 'package:kash_cube/data/services/sync/security/sync_key_rotation_policy.dart';

/// A fixed-clock policy wrapper for deterministic age tests in the checker.
class _FixedPolicy extends DefaultSyncKeyRotationPolicy {
  const _FixedPolicy({super.minAcceptableVersion = 1});
}

Map<String, dynamic> _peerRow({
  String id = 'peer-abc',
  String? pairedAt,
  String? keyRotatedAt,
  int? keyVersion,
}) {
  return <String, dynamic>{
    'peer_identity_id': id,
    'paired_at': pairedAt ?? DateTime.now().toUtc().toIso8601String(),
    'key_rotated_at': keyRotatedAt,
    'key_version': keyVersion,
  };
}

void main() {
  group('SyncKeyRotationChecker — fresh key', () {
    test('fresh key (1 hour old) returns SyncKeyRotationOk', () {
      final now = DateTime(2026, 4, 3, 12, 0, 0, 0).toUtc();
      final pairedAt = now.subtract(const Duration(hours: 1));
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final result = checker.evaluatePeerRow(
        _peerRow(pairedAt: pairedAt.toIso8601String()),
      );

      expect(result.status, isA<SyncKeyRotationOk>());
      expect(result.keyAgeDays, 0);
      expect(result.keyVersion, 1);
      expect(result.peerIdentityId, 'peer-abc');
    });
  });

  group('SyncKeyRotationChecker — age-based checking', () {
    test('key 45 days old returns SyncKeyRotationRecommended', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final pairedAt = now.subtract(const Duration(days: 45));
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final result = checker.evaluatePeerRow(
        _peerRow(pairedAt: pairedAt.toIso8601String()),
      );

      expect(result.status, isA<SyncKeyRotationRecommended>());
      expect(result.keyAgeDays, 45);
    });

    test('key 100 days old returns SyncKeyRotationRequired', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final pairedAt = now.subtract(const Duration(days: 100));
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final result = checker.evaluatePeerRow(
        _peerRow(pairedAt: pairedAt.toIso8601String()),
      );

      expect(result.status, isA<SyncKeyRotationRequired>());
      expect(result.keyAgeDays, 100);
    });
  });

  group(
    'SyncKeyRotationChecker — key_rotated_at takes precedence over paired_at',
    () {
      test('uses key_rotated_at when present, ignoring paired_at age', () {
        final now = DateTime(2026, 4, 3).toUtc();
        // paired_at is 200 days ago — would be Required if used as reference
        final pairedAt = now.subtract(const Duration(days: 200));
        // key_rotated_at is 5 days ago — should return Ok
        final rotatedAt = now.subtract(const Duration(days: 5));

        final checker = SyncKeyRotationChecker(
          policy: const _FixedPolicy(),
          clock: () => now,
        );

        final result = checker.evaluatePeerRow(
          _peerRow(
            pairedAt: pairedAt.toIso8601String(),
            keyRotatedAt: rotatedAt.toIso8601String(),
          ),
        );

        expect(result.status, isA<SyncKeyRotationOk>());
        expect(result.keyAgeDays, 5);
      });
    },
  );

  group('SyncKeyRotationChecker — key_version default for legacy rows', () {
    test(
      'row without key_version column uses version 1 (v85 migration default)',
      () {
        final now = DateTime(2026, 4, 3).toUtc();
        final checker = SyncKeyRotationChecker(
          policy: const _FixedPolicy(minAcceptableVersion: 1),
          clock: () => now,
        );

        // No key_version key in the map (simulates pre-v85 row).
        final row = <String, dynamic>{
          'peer_identity_id': 'legacy-peer',
          'paired_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        };

        final result = checker.evaluatePeerRow(row);
        expect(result.keyVersion, 1);
        expect(result.status, isA<SyncKeyRotationOk>());
      },
    );

    test(
      'version below minAcceptableVersion returns SyncKeyRotationRequired',
      () {
        final now = DateTime(2026, 4, 3).toUtc();
        final checker = SyncKeyRotationChecker(
          policy: const _FixedPolicy(minAcceptableVersion: 2),
          clock: () => now,
        );

        final result = checker.evaluatePeerRow(_peerRow(keyVersion: 1));
        expect(result.status, isA<SyncKeyRotationRequired>());
      },
    );

    test('version meeting minAcceptableVersion returns SyncKeyRotationOk', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(minAcceptableVersion: 2),
        clock: () => now,
      );

      final result = checker.evaluatePeerRow(_peerRow(keyVersion: 2));
      expect(result.status, isA<SyncKeyRotationOk>());
    });
  });

  group('SyncKeyRotationChecker — malformed / missing timestamps', () {
    test('missing paired_at defaults to age=0 → SyncKeyRotationOk', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final row = <String, dynamic>{
        'peer_identity_id': 'no-time-peer',
        // no paired_at
      };
      final result = checker.evaluatePeerRow(row);
      expect(result.keyAgeDays, 0);
      expect(result.status, isA<SyncKeyRotationOk>());
    });

    test('unparseable paired_at defaults to age=0', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final result = checker.evaluatePeerRow(_peerRow(pairedAt: 'not-a-date'));
      expect(result.keyAgeDays, 0);
      expect(result.status, isA<SyncKeyRotationOk>());
    });

    test('missing peer_identity_id defaults to empty string', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final row = <String, dynamic>{'paired_at': now.toIso8601String()};
      final result = checker.evaluatePeerRow(row);
      expect(result.peerIdentityId, '');
    });
  });

  group('SyncKeyRotationChecker.evaluateAll', () {
    test('returns one result per row in the same order', () {
      final now = DateTime(2026, 4, 3).toUtc();
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: () => now,
      );

      final rows = [
        _peerRow(
          id: 'peer-1',
          pairedAt: now.subtract(const Duration(days: 5)).toIso8601String(),
        ),
        _peerRow(
          id: 'peer-2',
          pairedAt: now.subtract(const Duration(days: 45)).toIso8601String(),
        ),
        _peerRow(
          id: 'peer-3',
          pairedAt: now.subtract(const Duration(days: 100)).toIso8601String(),
        ),
      ];

      final results = checker.evaluateAll(rows);
      expect(results, hasLength(3));
      expect(results[0].peerIdentityId, 'peer-1');
      expect(results[0].status, isA<SyncKeyRotationOk>());
      expect(results[1].peerIdentityId, 'peer-2');
      expect(results[1].status, isA<SyncKeyRotationRecommended>());
      expect(results[2].peerIdentityId, 'peer-3');
      expect(results[2].status, isA<SyncKeyRotationRequired>());
    });

    test('returns empty list for empty input', () {
      final checker = SyncKeyRotationChecker(
        policy: const _FixedPolicy(),
        clock: DateTime.now,
      );
      expect(checker.evaluateAll(<Map<String, dynamic>>[]), isEmpty);
    });
  });

  group('SyncKeyRotationResult fields', () {
    test(
      'keyAgeDays is computed from keyAgeSeconds truncated to whole days',
      () {
        final now = DateTime(2026, 4, 3, 12, 0, 0).toUtc();
        // 31 days and 8 hours → keyAgeDays should be 31 (truncated, not rounded)
        final pairedAt = now.subtract(const Duration(days: 31, hours: 8));
        final checker = SyncKeyRotationChecker(
          policy: const _FixedPolicy(),
          clock: () => now,
        );

        final result = checker.evaluatePeerRow(
          _peerRow(pairedAt: pairedAt.toIso8601String()),
        );
        expect(result.keyAgeDays, 31);
      },
    );
  });
}
