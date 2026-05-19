import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:cryptography/cryptography.dart';

import '../app_logger.dart';

/// Handles all cryptographic operations for P2P LAN sync.
///
/// Responsibilities:
///   1. Derive a 32-byte shared secret from two Ed25519 public keys via HKDF.
///   2. Encrypt / decrypt the shared secret at rest using AES-256-GCM.
///   3. Sign outgoing HTTP requests with HMAC-SHA256.
///   4. Verify incoming request signatures (X-Kash-Sig header).
///
/// Thread-safety: all methods are stateless (or use final fields).
/// No network calls — 100% on-device.
class P2pAuthService {
  P2pAuthService._();
  static final P2pAuthService instance = P2pAuthService._();

  static const _hkdfInfo = 'kashcube-p2p-v1';
  static const _clockSkewSeconds = 30;

  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ); // cryptography Hmac

  // ── 1. Shared secret derivation ──────────────────────────────────────────

  /// Derives a 32-byte shared secret from the two Ed25519 public key bytes.
  ///
  /// Input key material (IKM) is the concatenation of [localPubKey] and
  /// [remotePubKey], sorted lexicographically so both sides produce the same
  /// secret regardless of which party calls this first.
  ///
  /// The result is the raw 32-byte secret — pass it to [encryptSecret] before
  /// persisting.
  Future<Uint8List> deriveSharedSecret({
    required Uint8List localPubKey,
    required Uint8List remotePubKey,
  }) async {
    // Sort for commutativity — same output on both devices.
    final a = _bytesLessThan(localPubKey, remotePubKey)
        ? localPubKey
        : remotePubKey;
    final b = _bytesLessThan(localPubKey, remotePubKey)
        ? remotePubKey
        : localPubKey;

    final ikm = Uint8List(a.length + b.length)
      ..setRange(0, a.length, a)
      ..setRange(a.length, a.length + b.length, b);

    final secretKey = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: Uint8List(32), // zero salt → HKDF RFC 5869 §2.2 default
      info: utf8.encode(_hkdfInfo),
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  bool _bytesLessThan(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return a.length < b.length;
  }

  // ── 2. Secret encryption at rest (AES-256-GCM) ───────────────────────────

  /// Encrypts [rawSecret] with [deviceKey] (another 32-byte key, e.g. from
  /// the local Ed25519 private key bytes) and returns a base64 string suitable
  /// for storing in `trusted_peers.shared_secret_enc`.
  ///
  /// Format (base64): nonce(12) || ciphertext(32) || mac(16)
  Future<String> encryptSecret({
    required Uint8List rawSecret,
    required Uint8List deviceKey,
  }) async {
    final key = SecretKey(deviceKey.sublist(0, 32));
    final nonce = _randomBytes(12);
    final secretBox = await _aesGcm.encrypt(
      rawSecret,
      secretKey: key,
      nonce: nonce,
    );
    final combined =
        Uint8List(
            nonce.length +
                secretBox.cipherText.length +
                secretBox.mac.bytes.length,
          )
          ..setRange(0, nonce.length, nonce)
          ..setRange(
            nonce.length,
            nonce.length + secretBox.cipherText.length,
            secretBox.cipherText,
          )
          ..setRange(
            nonce.length + secretBox.cipherText.length,
            nonce.length +
                secretBox.cipherText.length +
                secretBox.mac.bytes.length,
            secretBox.mac.bytes,
          );
    return base64.encode(combined);
  }

  /// Decrypts a value produced by [encryptSecret]. Returns the raw 32-byte
  /// shared secret.
  Future<Uint8List> decryptSecret({
    required String encryptedBase64,
    required Uint8List deviceKey,
  }) async {
    final bytes = base64.decode(encryptedBase64);
    final nonce = bytes.sublist(0, 12);
    final cipher = bytes.sublist(12, bytes.length - 16);
    final mac = bytes.sublist(bytes.length - 16);

    final key = SecretKey(deviceKey.sublist(0, 32));
    final box = SecretBox(cipher, nonce: nonce, mac: Mac(mac));
    final plain = await _aesGcm.decrypt(box, secretKey: key);
    return Uint8List.fromList(plain);
  }

  // ── 3. Request signing (HMAC-SHA256) ─────────────────────────────────────

  /// Creates a proof that the caller knows [sharedSecret].
  /// Used in the back-pair notification so the receiver can verify the sender
  /// is legitimate before storing them as a trusted peer.
  ///
  /// proof = HMAC-SHA256(sharedSecret, "kc-pair:" + senderIdentityId)
  String signPairProof({
    required Uint8List sharedSecret,
    required String senderIdentityId,
  }) {
    final hmac = pkg_crypto.Hmac(pkg_crypto.sha256, sharedSecret);
    return hmac.convert(utf8.encode('kc-pair:$senderIdentityId')).toString();
  }

  /// Computes the `X-Kash-Sig` header value for an outgoing request.
  ///
  /// Signed string: `"$method\n$path\n$timestampIso\n$bodyHash"`
  ///   - [method]    : uppercase HTTP verb, e.g. `"POST"`
  ///   - [path]      : request path + query, e.g. `"/sync/push"`
  ///   - [timestamp] : ISO-8601 UTC timestamp (include this verbatim in header
  ///                   `X-Kash-Ts`)
  ///   - [body]      : raw request body bytes (empty list for GET)
  ///
  /// Returns the HMAC hex digest.
  String signRequest({
    required String method,
    required String path,
    required String timestamp,
    required List<int> body,
    required Uint8List sharedSecret,
  }) {
    final bodyHash = pkg_crypto.sha256.convert(body).toString();
    final message = '$method\n$path\n$timestamp\n$bodyHash';
    final hmac = pkg_crypto.Hmac(pkg_crypto.sha256, sharedSecret);
    return hmac.convert(utf8.encode(message)).toString();
  }

  /// Returns true if the request's HMAC signature is valid AND the timestamp
  /// is within [_clockSkewSeconds] of now.
  ///
  /// [receivedSig]  : value from `X-Kash-Sig` header
  /// [receivedTs]   : value from `X-Kash-Ts` header (ISO-8601)
  bool verifyRequest({
    required String method,
    required String path,
    required String receivedTs,
    required String receivedSig,
    required List<int> body,
    required Uint8List sharedSecret,
  }) {
    // 1. Check clock skew.
    DateTime ts;
    try {
      ts = DateTime.parse(receivedTs).toUtc();
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to parse P2P request timestamp',
        category: 'p2p_auth',
        error: e,
      );
      return false;
    }
    final skew = DateTime.now().toUtc().difference(ts).abs();
    if (skew.inSeconds > _clockSkewSeconds) return false;

    // 2. Re-derive expected HMAC and constant-time compare.
    final expected = signRequest(
      method: method,
      path: path,
      timestamp: receivedTs,
      body: body,
      sharedSecret: sharedSecret,
    );
    return _constantTimeEquals(expected, receivedSig);
  }

  // ── 4. Pairing nonce ─────────────────────────────────────────────────────

  /// Generates a 32-byte cryptographically random nonce for the QR code
  /// pairing handshake. Encoded as hex for embedding in the QR payload.
  String generatePairingNonce() =>
      _randomBytes(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // ── Helpers ──────────────────────────────────────────────────────────────

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  /// Constant-time string comparison to prevent timing attacks.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
