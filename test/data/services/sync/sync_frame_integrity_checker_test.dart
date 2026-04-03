import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/sync_frame_integrity_checker.dart';
import 'package:kash_cube/data/services/sync/transport/sync_signaling_messages.dart';

// A predictable secret for all tests.
final _secret = utf8.encode('test-secret-do-not-use-in-production');

HmacSyncFrameIntegrityChecker _hmac() =>
    HmacSyncFrameIntegrityChecker(secretBytes: _secret);

void main() {
  group('PassthroughSyncFrameIntegrityChecker', () {
    const checker = PassthroughSyncFrameIntegrityChecker();

    test('sign returns defensive copy of frame unchanged', () {
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'table': 'transactions',
        'sync_id': 'x1',
      };
      final result = checker.sign(frame);
      expect(result, equals(frame));
      expect(identical(result, frame), isFalse);
    });

    test('verify returns defensive copy of frame unchanged', () {
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.push,
        'table': 'transactions',
        'rows': <dynamic>[],
      };
      final result = checker.verify(frame);
      expect(result, isNotNull);
      expect(result, equals(frame));
      expect(identical(result, frame), isFalse);
    });

    test('passthrough does not add _kash_sig field', () {
      final frame = <String, dynamic>{'type': SyncSignalingMessages.rows};
      expect(checker.sign(frame).containsKey('_kash_sig'), isFalse);
    });
  });

  group('HmacSyncFrameIntegrityChecker — sign', () {
    test('adds _kash_sig to data-plane frames', () {
      final checker = _hmac();
      for (final type in [
        SyncSignalingMessages.write,
        SyncSignalingMessages.writeOk,
        SyncSignalingMessages.rows,
        SyncSignalingMessages.push,
        SyncSignalingMessages.pull,
        SyncSignalingMessages.syncPlan,
      ]) {
        final frame = <String, dynamic>{'type': type, 'sync_id': 'abc'};
        final signed = checker.sign(frame);
        expect(signed.containsKey('_kash_sig'), isTrue,
            reason: 'type=$type should be signed');
        expect(signed['_kash_sig'], isA<String>());
        expect((signed['_kash_sig'] as String).isNotEmpty, isTrue);
      }
    });

    test('does not add _kash_sig to control-plane frames', () {
      final checker = _hmac();
      for (final type in [
        SyncSignalingMessages.ping,
        SyncSignalingMessages.pong,
        SyncSignalingMessages.auth,
        SyncSignalingMessages.authOk,
        SyncSignalingMessages.sessionAuth,
        SyncSignalingMessages.signalOffer,
        SyncSignalingMessages.signalAnswer,
        SyncSignalingMessages.signalIceCandidate,
      ]) {
        final frame = <String, dynamic>{'type': type};
        final signed = checker.sign(frame);
        expect(signed.containsKey('_kash_sig'), isFalse,
            reason: 'control-plane type=$type should not be signed');
      }
    });

    test('sign returns a defensive copy not the original map', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'q1',
      };
      final signed = checker.sign(frame);
      signed['injected'] = true;
      expect(frame.containsKey('injected'), isFalse);
    });

    test('original payload fields are preserved after signing', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'table': 'credits',
        'sync_id': 'syn-42',
        'row': <String, dynamic>{'id': 1},
      };
      final signed = checker.sign(frame);
      expect(signed['type'], SyncSignalingMessages.write);
      expect(signed['table'], 'credits');
      expect(signed['sync_id'], 'syn-42');
      expect(signed['row'], isA<Map>());
    });
  });

  group('HmacSyncFrameIntegrityChecker — verify', () {
    test('verify accepts valid signed data-plane frame and strips sig', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.push,
        'table': 'transactions',
        'rows': <dynamic>[<String, dynamic>{'sync_id': 'r1'}],
      };
      final signed = checker.sign(frame);
      final verified = checker.verify(signed);

      expect(verified, isNotNull);
      expect(verified!.containsKey('_kash_sig'), isFalse);
      expect(verified['type'], SyncSignalingMessages.push);
      expect(verified['table'], 'transactions');
    });

    test('verify returns null for data-plane frame missing sig', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'no-sig',
      };
      expect(checker.verify(frame), isNull);
    });

    test('verify returns null for data-plane frame with tampered sig', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.rows,
        'table': 'transactions',
        'sync_id': 'tamper-1',
      };
      final signed = checker.sign(frame);
      final tampered = Map<String, dynamic>.from(signed);
      tampered['_kash_sig'] = 'deadbeef' * 8; // wrong sig, same length
      expect(checker.verify(tampered), isNull);
    });

    test('verify returns null for data-plane frame with body mutation after sign', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'tamper-2',
        'table': 'transactions',
      };
      final signed = checker.sign(frame);
      final mutated = Map<String, dynamic>.from(signed);
      mutated['table'] = 'loans'; // body changed after signing
      expect(checker.verify(mutated), isNull);
    });

    test('verify passes through control-plane frames without sig requirement', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.ping,
        'ts': 1234567890,
      };
      final result = checker.verify(frame);
      expect(result, isNotNull);
      expect(result!['type'], SyncSignalingMessages.ping);
    });

    test('verify returns null for frame with missing type field', () {
      final checker = _hmac();
      expect(checker.verify(<String, dynamic>{'sync_id': 'x'}), isNull);
    });

    test('signed frame verifies with same secret but not with different secret', () {
      final checker1 = HmacSyncFrameIntegrityChecker(
        secretBytes: utf8.encode('secret-a'),
      );
      final checker2 = HmacSyncFrameIntegrityChecker(
        secretBytes: utf8.encode('secret-b'),
      );
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'cross-key-1',
      };

      final signed = checker1.sign(frame);
      expect(checker1.verify(signed), isNotNull);
      expect(checker2.verify(signed), isNull);
    });
  });

  group('HmacSyncFrameIntegrityChecker — canonicalization', () {
    test('sign is deterministic: same frame always produces same sig', () {
      final checker = _hmac();
      final frame = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'det-1',
        'table': 'transactions',
      };
      final sig1 = checker.sign(frame)['_kash_sig'];
      final sig2 = checker.sign(frame)['_kash_sig'];
      expect(sig1, sig2);
    });

    test('different field insertion order produces same sig (key sort)', () {
      final checker = _hmac();
      final frameA = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'sort-1',
        'table': 'transactions',
      };
      final frameB = <String, dynamic>{
        'table': 'transactions',
        'sync_id': 'sort-1',
        'type': SyncSignalingMessages.write,
      };
      expect(checker.sign(frameA)['_kash_sig'],
          equals(checker.sign(frameB)['_kash_sig']));
    });

    test('sig changes when any payload field value changes', () {
      final checker = _hmac();
      final frameA = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'val-1',
      };
      final frameB = <String, dynamic>{
        'type': SyncSignalingMessages.write,
        'sync_id': 'val-2',
      };
      expect(checker.sign(frameA)['_kash_sig'],
          isNot(equals(checker.sign(frameB)['_kash_sig'])));
    });
  });

  group('SyncFrameIntegrityChecker — cloud transport integration', () {
    test('sign + verify round-trip for all data-plane types', () {
      final checker = _hmac();
      for (final type in [
        SyncSignalingMessages.write,
        SyncSignalingMessages.writeOk,
        SyncSignalingMessages.rows,
        SyncSignalingMessages.push,
        SyncSignalingMessages.pull,
        SyncSignalingMessages.syncPlan,
      ]) {
        final frame = <String, dynamic>{
          'type': type,
          'sync_id': 'roundtrip-$type',
          'payload': 'data',
        };
        final signed = checker.sign(frame);
        final verified = checker.verify(signed);
        expect(verified, isNotNull,
            reason: 'round-trip failed for type=$type');
        expect(verified!['type'], type);
        expect(verified['sync_id'], 'roundtrip-$type');
        expect(verified.containsKey('_kash_sig'), isFalse);
      }
    });
  });
}
