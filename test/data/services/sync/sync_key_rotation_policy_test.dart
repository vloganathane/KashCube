import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/security/sync_key_rotation_policy.dart';

void main() {
  group('DefaultSyncKeyRotationPolicy — version check', () {
    const policy = DefaultSyncKeyRotationPolicy(minAcceptableVersion: 2);

    test(
      'returns SyncKeyRotationRequired when keyVersion < minAcceptableVersion',
      () {
        final result = policy.evaluate(keyVersion: 1, keyAgeSeconds: 0);
        expect(result, isA<SyncKeyRotationRequired>());
        final req = result as SyncKeyRotationRequired;
        expect(req.reason, contains('1'));
        expect(req.reason, contains('2'));
      },
    );

    test(
      'returns SyncKeyRotationOk when keyVersion == minAcceptableVersion',
      () {
        final result = policy.evaluate(keyVersion: 2, keyAgeSeconds: 0);
        expect(result, isA<SyncKeyRotationOk>());
      },
    );

    test(
      'returns SyncKeyRotationOk when keyVersion > minAcceptableVersion',
      () {
        final result = policy.evaluate(keyVersion: 5, keyAgeSeconds: 0);
        expect(result, isA<SyncKeyRotationOk>());
      },
    );
  });

  group('DefaultSyncKeyRotationPolicy — age thresholds', () {
    const policy = DefaultSyncKeyRotationPolicy(
      minAcceptableVersion: 1,
      recommendRotationAfterDays: 30,
      maxKeyAgeDays: 90,
    );

    test('returns SyncKeyRotationOk for a fresh key (0 days)', () {
      final result = policy.evaluate(keyVersion: 1, keyAgeSeconds: 0);
      expect(result, isA<SyncKeyRotationOk>());
    });

    test(
      'returns SyncKeyRotationOk at exactly recommendRotationAfterDays boundary (30 days)',
      () {
        // Exactly 30 days is NOT past the threshold (> not >=).
        final result = policy.evaluate(
          keyVersion: 1,
          keyAgeSeconds: 30 * 86400,
        );
        expect(result, isA<SyncKeyRotationOk>());
      },
    );

    test('returns SyncKeyRotationRecommended for key 31 days old', () {
      final result = policy.evaluate(keyVersion: 1, keyAgeSeconds: 31 * 86400);
      expect(result, isA<SyncKeyRotationRecommended>());
      final rec = result as SyncKeyRotationRecommended;
      expect(rec.reason, contains('31'));
    });

    test(
      'returns SyncKeyRotationRecommended at exactly maxKeyAgeDays boundary (90 days)',
      () {
        // 90 > 30 (recommendRotationAfterDays) but NOT > 90 (maxKeyAgeDays),
        // so rotation is recommended but not yet required.
        final result = policy.evaluate(
          keyVersion: 1,
          keyAgeSeconds: 90 * 86400,
        );
        expect(result, isA<SyncKeyRotationRecommended>());
      },
    );

    test('returns SyncKeyRotationRequired for key 91 days old', () {
      final result = policy.evaluate(keyVersion: 1, keyAgeSeconds: 91 * 86400);
      expect(result, isA<SyncKeyRotationRequired>());
      final req = result as SyncKeyRotationRequired;
      expect(req.reason, contains('91'));
    });

    test('returns SyncKeyRotationRequired for a very old key (365 days)', () {
      final result = policy.evaluate(keyVersion: 1, keyAgeSeconds: 365 * 86400);
      expect(result, isA<SyncKeyRotationRequired>());
    });
  });

  group('DefaultSyncKeyRotationPolicy — version floor beats age check', () {
    test(
      'version floor is evaluated before age -> Required even for fresh key',
      () {
        final policy = DefaultSyncKeyRotationPolicy(minAcceptableVersion: 3);
        final result = policy.evaluate(keyVersion: 2, keyAgeSeconds: 0);
        // Version 2 < min 3 → Required, regardless of age = 0
        expect(result, isA<SyncKeyRotationRequired>());
      },
    );
  });

  group('DefaultSyncKeyRotationPolicy — default values', () {
    const policy = DefaultSyncKeyRotationPolicy();

    test('default minAcceptableVersion is 1 — v1 keys are accepted', () {
      final result = policy.evaluate(keyVersion: 1, keyAgeSeconds: 0);
      expect(result, isA<SyncKeyRotationOk>());
    });

    test('default recommendRotationAfterDays is 30', () {
      final ok = policy.evaluate(keyVersion: 1, keyAgeSeconds: 30 * 86400);
      expect(ok, isA<SyncKeyRotationOk>());

      final rec = policy.evaluate(keyVersion: 1, keyAgeSeconds: 31 * 86400);
      expect(rec, isA<SyncKeyRotationRecommended>());
    });

    test('default maxKeyAgeDays is 90', () {
      // At exactly 90 days: NOT > 90, so not Required;
      // but 90 > 30 (recommendRotationAfterDays), so Recommended.
      final rec = policy.evaluate(keyVersion: 1, keyAgeSeconds: 90 * 86400);
      expect(rec, isA<SyncKeyRotationRecommended>());

      final req = policy.evaluate(keyVersion: 1, keyAgeSeconds: 91 * 86400);
      expect(req, isA<SyncKeyRotationRequired>());
    });
  });

  group('SyncKeyRotationStatus sealed type completeness', () {
    test('sealed types are distinguishable', () {
      const ok = SyncKeyRotationOk();
      const rec = SyncKeyRotationRecommended(reason: 'r');
      const req = SyncKeyRotationRequired(reason: 'r');
      expect(ok, isA<SyncKeyRotationOk>());
      expect(rec, isA<SyncKeyRotationRecommended>());
      expect(req, isA<SyncKeyRotationRequired>());
    });

    test('reason field is accessible on SyncKeyRotationRecommended', () {
      const rec = SyncKeyRotationRecommended(reason: 'test reason');
      expect(rec.reason, 'test reason');
    });

    test('reason field is accessible on SyncKeyRotationRequired', () {
      const req = SyncKeyRotationRequired(reason: 'test reason');
      expect(req.reason, 'test reason');
    });
  });
}
