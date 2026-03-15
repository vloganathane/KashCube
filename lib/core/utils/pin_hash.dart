import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// ---------------------------------------------------------------------------
// PIN hashing — PBKDF2-HMAC-SHA256 with a random per-user salt
// ---------------------------------------------------------------------------
//
// Format stored in the DB / settings:
//   "v2:{saltHex}:{hashHex}"    ← new PBKDF2 hashes
//   "{64-char sha256 hex}"       ← legacy (SHA-256 only, no salt)
//
// Legacy hashes are still accepted by [verifyPin] for backward compatibility.
// After a successful legacy verification, call [hashPin] and re-store the
// result so the account silently upgrades to PBKDF2 on next unlock.
// ---------------------------------------------------------------------------

const _saltLength = 16;
const _pbkdf2Iterations = 100000;

/// Hashes a PIN using PBKDF2-HMAC-SHA256 with a random 16-byte salt.
/// Returns a string of the form `"v2:{saltHex}:{hashHex}"`.
String hashPin(String pin) {
  final rng = Random.secure();
  final salt = Uint8List.fromList(
    List<int>.generate(_saltLength, (_) => rng.nextInt(256)),
  );
  final hash = _pbkdf2(utf8.encode(pin), salt);
  return 'v2:${_toHex(salt)}:${_toHex(hash)}';
}

/// Returns `true` if [enteredPin] matches [storedHash].
///
/// Accepts both PBKDF2 (`"v2:..."`) and legacy SHA-256 hashes.
/// Uses constant-time comparison to prevent timing attacks.
bool verifyPin(String enteredPin, String storedHash) {
  if (storedHash.startsWith('v2:')) {
    final parts = storedHash.split(':');
    if (parts.length != 3) return false;
    final salt = _fromHex(parts[1]);
    final expected = _fromHex(parts[2]);
    final actual = _pbkdf2(utf8.encode(enteredPin), salt);
    return _constantTimeEquals(actual, expected);
  }
  // Legacy: bare SHA-256 hex — constant-time compare.
  final entered = sha256.convert(utf8.encode(enteredPin)).toString();
  return _constantTimeEquals(
    Uint8List.fromList(utf8.encode(entered)),
    Uint8List.fromList(utf8.encode(storedHash)),
  );
}

/// Returns `true` when [storedHash] was created by the old SHA-256 scheme
/// and should be re-hashed with PBKDF2 after the next successful unlock.
bool pinHashNeedsUpgrade(String storedHash) => !storedHash.startsWith('v2:');

// ── Internals ──────────────────────────────────────────────────────────────

/// PBKDF2-HMAC-SHA256: single block (32-byte output), [_pbkdf2Iterations] rounds.
Uint8List _pbkdf2(List<int> password, Uint8List salt) {
  final seedData = Uint8List(salt.length + 4);
  seedData.setRange(0, salt.length, salt);
  seedData[salt.length + 3] = 1; // Block index INT(1) big-endian

  final hmac = Hmac(sha256, password);
  var u = Uint8List.fromList(hmac.convert(seedData).bytes);
  final result = Uint8List.fromList(u);

  for (var i = 1; i < _pbkdf2Iterations; i++) {
    u = Uint8List.fromList(Hmac(sha256, password).convert(u).bytes);
    for (var j = 0; j < 32; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final len = hex.length ~/ 2;
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Constant-time byte comparison — prevents timing-based side-channel attacks.
bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
