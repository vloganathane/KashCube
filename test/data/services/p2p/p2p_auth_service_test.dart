import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/p2p/p2p_auth_service.dart';

void main() {
  final auth = P2pAuthService.instance;

  // Deterministic 32-byte "public key" stand-ins for HKDF tests.
  final keyA = Uint8List.fromList(List.generate(32, (i) => i + 1));       // 01..20
  final keyB = Uint8List.fromList(List.generate(32, (i) => 200 - i));     // c8..a9

  // Deterministic device key for encrypt/decrypt tests.
  final deviceKey = Uint8List.fromList(List.generate(32, (i) => i * 3 % 256));

  group('P2pAuthService.deriveSharedSecret', () {
    test('produces a 32-byte secret', () async {
      final secret = await auth.deriveSharedSecret(
        localPubKey:  keyA,
        remotePubKey: keyB,
      );
      expect(secret.length, 32);
    });

    test('is commutative — A+B == B+A', () async {
      final ab = await auth.deriveSharedSecret(
        localPubKey:  keyA,
        remotePubKey: keyB,
      );
      final ba = await auth.deriveSharedSecret(
        localPubKey:  keyB,
        remotePubKey: keyA,
      );
      expect(ab, ba);
    });

    test('different key pairs produce different secrets', () async {
      final keyC = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final ab = await auth.deriveSharedSecret(
        localPubKey: keyA, remotePubKey: keyB,
      );
      final ac = await auth.deriveSharedSecret(
        localPubKey: keyA, remotePubKey: keyC,
      );
      expect(ab, isNot(ac));
    });

    test('is deterministic — same inputs always give same output', () async {
      final s1 = await auth.deriveSharedSecret(localPubKey: keyA, remotePubKey: keyB);
      final s2 = await auth.deriveSharedSecret(localPubKey: keyA, remotePubKey: keyB);
      expect(s1, s2);
    });
  });

  group('P2pAuthService encrypt/decrypt round-trip', () {
    test('decryptSecret recovers the original bytes', () async {
      final secret  = Uint8List.fromList(List.generate(32, (i) => i + 50));
      final enc     = await auth.encryptSecret(rawSecret: secret, deviceKey: deviceKey);
      final decoded = await auth.decryptSecret(encryptedBase64: enc, deviceKey: deviceKey);
      expect(decoded, secret);
    });

    test('different nonces each call — two encryptions differ', () async {
      final secret = Uint8List.fromList(List.generate(32, (_) => 0xAB));
      final enc1   = await auth.encryptSecret(rawSecret: secret, deviceKey: deviceKey);
      final enc2   = await auth.encryptSecret(rawSecret: secret, deviceKey: deviceKey);
      expect(enc1, isNot(enc2)); // nonce is random per call
    });

    test('wrong device key cannot decrypt', () async {
      final secret   = Uint8List.fromList(List.generate(32, (i) => i));
      final enc      = await auth.encryptSecret(rawSecret: secret, deviceKey: deviceKey);
      final wrongKey = Uint8List.fromList(List.generate(32, (_) => 0xFF));
      expect(
        () => auth.decryptSecret(encryptedBase64: enc, deviceKey: wrongKey),
        throwsA(anything),
      );
    });
  });

  group('P2pAuthService signRequest + verifyRequest', () {
    final sharedSecret = Uint8List.fromList(List.generate(32, (i) => i + 10));
    final ts = DateTime.now().toUtc().toIso8601String();
    const body = <int>[];

    test('valid signature passes verification', () {
      final sig = auth.signRequest(
        method: 'POST', path: '/sync/pull', timestamp: ts,
        body: body, sharedSecret: sharedSecret,
      );
      expect(
        auth.verifyRequest(
          method: 'POST', path: '/sync/pull', receivedTs: ts,
          body: body, sharedSecret: sharedSecret, receivedSig: sig,
        ),
        isTrue,
      );
    });

    test('tampered signature is rejected', () {
      final sig = auth.signRequest(
        method: 'POST', path: '/sync/pull', timestamp: ts,
        body: body, sharedSecret: sharedSecret,
      );
      final tampered = '${sig.substring(0, sig.length - 2)}00';
      expect(
        auth.verifyRequest(
          method: 'POST', path: '/sync/pull', receivedTs: ts,
          body: body, sharedSecret: sharedSecret, receivedSig: tampered,
        ),
        isFalse,
      );
    });

    test('wrong path is rejected', () {
      final sig = auth.signRequest(
        method: 'POST', path: '/sync/pull', timestamp: ts,
        body: body, sharedSecret: sharedSecret,
      );
      expect(
        auth.verifyRequest(
          method: 'POST', path: '/sync/push', receivedTs: ts,
          body: body, sharedSecret: sharedSecret, receivedSig: sig,
        ),
        isFalse,
      );
    });

    test('stale timestamp is rejected (>30s skew)', () {
      final staleTs = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 60))
          .toIso8601String();
      final sig = auth.signRequest(
        method: 'GET', path: '/hello', timestamp: staleTs,
        body: body, sharedSecret: sharedSecret,
      );
      expect(
        auth.verifyRequest(
          method: 'GET', path: '/hello', receivedTs: staleTs,
          body: body, sharedSecret: sharedSecret, receivedSig: sig,
        ),
        isFalse,
      );
    });

    test('wrong shared secret is rejected', () {
      final sig = auth.signRequest(
        method: 'POST', path: '/sync/push', timestamp: ts,
        body: body, sharedSecret: sharedSecret,
      );
      final wrongSecret = Uint8List.fromList(List.generate(32, (_) => 0xFF));
      expect(
        auth.verifyRequest(
          method: 'POST', path: '/sync/push', receivedTs: ts,
          body: body, sharedSecret: wrongSecret, receivedSig: sig,
        ),
        isFalse,
      );
    });

    test('body bytes are included in signature — body mutation detected', () {
      final bodyWithData = [1, 2, 3, 4];
      final sig = auth.signRequest(
        method: 'POST', path: '/sync/push', timestamp: ts,
        body: bodyWithData, sharedSecret: sharedSecret,
      );
      expect(
        auth.verifyRequest(
          method: 'POST', path: '/sync/push', receivedTs: ts,
          body: [1, 2, 3, 5], // mutated last byte
          sharedSecret: sharedSecret, receivedSig: sig,
        ),
        isFalse,
      );
    });
  });

  group('P2pAuthService.generatePairingNonce', () {
    test('returns 64 hex characters (32 bytes)', () {
      final nonce = auth.generatePairingNonce();
      expect(nonce.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce), isTrue);
    });

    test('successive calls return different nonces', () {
      final n1 = auth.generatePairingNonce();
      final n2 = auth.generatePairingNonce();
      expect(n1, isNot(n2));
    });
  });
}
