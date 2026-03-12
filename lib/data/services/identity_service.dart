import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/settings_repository.dart';
import '../../presentation/providers/settings_provider.dart';

/// Manages the device's Ed25519 identity.
///
/// On first run, generates a keypair and stores:
/// - Private key seed (32 bytes) → [FlutterSecureStorage] under
///   [_kPrivateKeyStorageKey].
/// - Public key (32 bytes as base64) → [SettingsRepository] under
///   [SettingsKeys.primaryPublicKey].
/// - Random device UUID → [SettingsRepository] under [SettingsKeys.deviceId].
/// - Device display name → [SettingsRepository] under [SettingsKeys.deviceName].
///
/// On subsequent runs, the existing keys are loaded from storage.
///
/// Usage:
/// ```dart
/// await IdentityService.instance.ensureInitialized(settingsRepo);
/// final id  = await IdentityService.instance.deviceId;
/// final sig = await IdentityService.instance.sign(message);
/// ```
class IdentityService {
  IdentityService._();
  static final IdentityService instance = IdentityService._();

  static const String _kPrivateKeyStorageKey = 'primary_signing_key';

  final _algo    = Ed25519();
  final _storage = const FlutterSecureStorage();

  SimpleKeyPair? _keyPair;
  String? _deviceId;
  String? _publicKeyBase64;

  bool get isInitialized => _keyPair != null;

  /// Call once at app startup (before any sync operation).
  Future<void> ensureInitialized(SettingsRepository settings) async {
    if (_keyPair != null) return;

    // ── Load or generate device_id ──────────────────────────────────────────
    String? storedId = await settings.get(SettingsKeys.deviceId);
    if (storedId == null || storedId.isEmpty) {
      storedId = const Uuid().v4();
      await settings.set(SettingsKeys.deviceId, storedId);
    }
    _deviceId = storedId;

    // ── Load or generate device_name ────────────────────────────────────────
    final storedName = await settings.get(SettingsKeys.deviceName);
    if (storedName == null || storedName.isEmpty) {
      final name = Platform.localHostname;
      await settings.set(SettingsKeys.deviceName, name);
    }

    // ── Load or generate Ed25519 keypair ────────────────────────────────────
    final seedB64 = await _storage.read(key: _kPrivateKeyStorageKey);
    if (seedB64 != null && seedB64.isNotEmpty) {
      // Restore from stored seed
      final seed = base64.decode(seedB64);
      _keyPair = await _algo.newKeyPairFromSeed(seed);
    } else {
      // First-time key generation
      _keyPair = await _algo.newKeyPair();
      final seed = await _keyPair!.extractPrivateKeyBytes();
      await _storage.write(
        key: _kPrivateKeyStorageKey,
        value: base64.encode(seed),
      );
    }

    // Persist / refresh public key in settings so secondary devices can verify
    final pubKey = await _keyPair!.extractPublicKey();
    _publicKeyBase64 = base64.encode(pubKey.bytes);
    await settings.set(SettingsKeys.primaryPublicKey, _publicKeyBase64!);
  }

  Future<String> get deviceId async {
    if (_deviceId != null) return _deviceId!;
    throw StateError('IdentityService not initialized — call ensureInitialized first');
  }

  Future<String> get publicKeyBase64 async {
    if (_publicKeyBase64 != null) return _publicKeyBase64!;
    throw StateError('IdentityService not initialized — call ensureInitialized first');
  }

  /// Signs [message] bytes with the device private key.
  /// Returns a [Signature] whose [Signature.bytes] are 64 bytes (base64-able).
  Future<Signature> sign(List<int> message) async {
    _assertInitialized();
    return _algo.sign(message, keyPair: _keyPair!);
  }

  /// Verifies that [sigBase64] was produced by the key at [publicKeyBase64] over [message].
  Future<bool> verify({
    required List<int> message,
    required String sigBase64,
    required String publicKeyBase64,
  }) async {
    final pk = SimplePublicKey(
      base64.decode(publicKeyBase64),
      type: KeyPairType.ed25519,
    );
    final sig = Signature(base64.decode(sigBase64), publicKey: pk);
    return _algo.verify(message, signature: sig);
  }

  void _assertInitialized() {
    if (_keyPair == null) {
      throw StateError('IdentityService not initialized — call ensureInitialized first');
    }
  }

  /// Resets in-memory state (for testing only).
  void reset() {
    _keyPair         = null;
    _deviceId        = null;
    _publicKeyBase64 = null;
  }
}
