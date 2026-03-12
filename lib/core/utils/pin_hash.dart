import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Hashes a PIN using SHA-256.
/// Used for both the owner PIN (stored in settings) and app user PINs
/// (stored in app_users.pin_hash). SHA-256 + brute-force lockout is
/// sufficient for a local 4-digit PIN.
String hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

/// Returns true if [enteredPin] matches [storedHash].
bool verifyPin(String enteredPin, String storedHash) =>
    hashPin(enteredPin) == storedHash;
