import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/settings_repository.dart';
import '../../presentation/providers/settings_provider.dart';

/// Manages the device's Ed25519 identities.
///
/// **Device signing key** (`primary_signing_key`): used to sign sync tokens.
/// **Identity keypair** (`identity_private_key`): the permanent per-install
/// identity used for dual-primary pairing (Phase D1+).
///
/// On first run, both keypairs are generated and stored:
/// - Private key seeds (32 bytes) → [FlutterSecureStorage].
/// - Device public key → [SettingsRepository] under [SettingsKeys.primaryPublicKey].
/// - Identity public key → `my_identity` table (`public_key` column).
/// - Device UUID → [SettingsRepository] under [SettingsKeys.deviceId].
///
/// Usage:
/// ```dart
/// await IdentityService.instance.ensureInitialized(settingsRepo);
/// await IdentityService.instance.ensureIdentityInitialized(db, 'Alice');
/// final sig = await IdentityService.instance.sign(message);
/// ```
class IdentityService {
  IdentityService._();
  static final IdentityService instance = IdentityService._();

  static const String _kPrivateKeyStorageKey = 'primary_signing_key';
  static const String _kIdentityKeyStorageKey = 'identity_private_key';

  final _algo    = Ed25519();
  final _storage = const FlutterSecureStorage();

  // ── Device signing keypair (Sprint 3 / sync tokens) ─────────────────────
  SimpleKeyPair? _keyPair;
  String? _deviceId;
  String? _publicKeyBase64;

  // ── Identity keypair (Sprint 5 / dual-primary) ───────────────────────────
  SimpleKeyPair? _identityKeyPair;
  String? _identityId;
  String? _identityPublicKeyBase64;

  bool get isInitialized => _keyPair != null;
  bool get isIdentityInitialized => _identityKeyPair != null;

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
      final name = kIsWeb ? 'KashCube Web' : Platform.localHostname;
      await settings.set(SettingsKeys.deviceName, name);
    }

    // ── Load or generate Ed25519 signing keypair ─────────────────────────────
    final seedB64 = await _storage.read(key: _kPrivateKeyStorageKey);
    if (seedB64 != null && seedB64.isNotEmpty) {
      final seed = base64.decode(seedB64);
      _keyPair = await _algo.newKeyPairFromSeed(seed);
    } else {
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

  /// Ensures the permanent identity keypair exists and the `my_identity` row
  /// is populated.  Call after [ensureInitialized] and DB open.
  ///
  /// [displayName] is only used when creating the identity for the FIRST time
  /// (fresh install).  On subsequent calls the existing name is preserved.
  Future<void> ensureIdentityInitialized(
    Database db, {
    String displayName = 'Me',
  }) async {
    if (_identityKeyPair != null) return;

    // ── Load or generate identity keypair ───────────────────────────────────
    final seedB64 = await _storage.read(key: _kIdentityKeyStorageKey);
    if (seedB64 != null && seedB64.isNotEmpty) {
      final seed = base64.decode(seedB64);
      _identityKeyPair = await _algo.newKeyPairFromSeed(seed);
    } else {
      _identityKeyPair = await _algo.newKeyPair();
      final seed = await _identityKeyPair!.extractPrivateKeyBytes();
      await _storage.write(
        key: _kIdentityKeyStorageKey,
        value: base64.encode(seed),
      );
    }

    final pubKey = await _identityKeyPair!.extractPublicKey();
    _identityPublicKeyBase64 = base64.encode(pubKey.bytes);

    // ── Load or create my_identity row ─────────────────────────────────────
    final rows = await db.query('my_identity', limit: 1);
    if (rows.isEmpty) {
      _identityId = const Uuid().v4();
      await db.insert('my_identity', {
        'id':           1,
        'identity_id':  _identityId,
        'display_name': displayName,
        'public_key':   _identityPublicKeyBase64,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      _identityId = rows.first['identity_id'] as String;
      // Refresh public key if it has changed (key rotation / restore)
      final storedPk = rows.first['public_key'] as String?;
      if (storedPk != _identityPublicKeyBase64) {
        await db.update(
          'my_identity',
          {'public_key': _identityPublicKeyBase64, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = 1',
        );
      }
    }
  }

  // ── Device signing key accessors ─────────────────────────────────────────

  Future<String> get deviceId async {
    if (_deviceId != null) return _deviceId!;
    throw StateError('IdentityService not initialized — call ensureInitialized first');
  }

  Future<String> get publicKeyBase64 async {
    if (_publicKeyBase64 != null) return _publicKeyBase64!;
    throw StateError('IdentityService not initialized — call ensureInitialized first');
  }

  // ── Identity keypair accessors ────────────────────────────────────────────

  String get identityId {
    if (_identityId != null) return _identityId!;
    throw StateError('IdentityService identity not initialized — call ensureIdentityInitialized first');
  }

  String get identityPublicKeyBase64 {
    if (_identityPublicKeyBase64 != null) return _identityPublicKeyBase64!;
    throw StateError('IdentityService identity not initialized — call ensureIdentityInitialized first');
  }

  /// Returns the JSON string used for the identity QR code.
  /// Fields: identity_id, identity_public_key.
  String identityQrPayload() {
    return jsonEncode({
      'identity_id':         identityId,
      'identity_public_key': identityPublicKeyBase64,
    });
  }

  /// Returns the base64-encoded private key seed for backup export.
  Future<String?> exportIdentityPrivateKeySeed() async {
    return _storage.read(key: _kIdentityKeyStorageKey);
  }

  /// Restores the identity private key from a backup seed and re-derives the
  /// keypair.  Call before [ensureIdentityInitialized] or after clearing state.
  Future<void> importIdentityPrivateKeySeed(String seedBase64) async {
    await _storage.write(key: _kIdentityKeyStorageKey, value: seedBase64);
    // Invalidate cached keypair so ensureIdentityInitialized reloads it
    _identityKeyPair = null;
    _identityId = null;
    _identityPublicKeyBase64 = null;
  }

  // ── Signing / verification ────────────────────────────────────────────────

  /// Signs [message] bytes with the device signing private key.
  Future<Signature> sign(List<int> message) async {
    _assertInitialized();
    return _algo.sign(message, keyPair: _keyPair!);
  }

  /// Signs [message] bytes with the identity private key.
  Future<Signature> signWithIdentity(List<int> message) async {
    if (_identityKeyPair == null) {
      throw StateError('IdentityService identity not initialized');
    }
    return _algo.sign(message, keyPair: _identityKeyPair!);
  }

  /// Verifies that [sigBase64] was produced by [publicKeyBase64] over [message].
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
    _keyPair                  = null;
    _deviceId                 = null;
    _publicKeyBase64          = null;
    _identityKeyPair          = null;
    _identityId               = null;
    _identityPublicKeyBase64  = null;
  }
}
