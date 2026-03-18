import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';

// ---------------------------------------------------------------------------
// Encrypted .kashcube Backup Format
// ---------------------------------------------------------------------------
//
//  Offset  Size  Field
//  ------  ----  ---------
//    0       4   magic "KSHC"
//    4       1   format version = 1
//    5      16   PBKDF2 salt (random)
//   21      12   AES-GCM IV / nonce (random)
//   33       4   DB schema version, big-endian uint32 (unencrypted metadata)
//   37       N   AES-256-GCM ciphertext  ← includes 16-byte auth tag appended
//
// Encrypted payload (before AES-GCM):
//    0       4   manifest JSON byte length, big-endian uint32
//    4       M   manifest JSON (UTF-8)
//  4+M       R   raw bytes of kash_cube.db
//
// Key derivation: PBKDF2-HMAC-SHA256(passphrase, salt, 100_000 iters) → 32 B
//
// PRIVACY: No data ever leaves the device. The .kashcube file is only moved
//          off-device if the user explicitly shares it via the OS share sheet.
// ---------------------------------------------------------------------------

// ── Constants ──────────────────────────────────────────────────────────────

const _magic = 'KSHC';
const _fmtVersion = 1;
const _saltLength = 16;
const _ivLength = 12;
const _schemaFieldLength = 4;
const _pbkdf2Iterations = 100000;
const _maxAttempts = 5;
const _lockoutMinutes = 15;

// SharedPreferences keys
const _prefAttempts = 'enc_backup_attempts';
const _prefLockedUntil = 'enc_backup_locked_until';
const _prefLastBackupDate = 'last_backup_date';
const _prefAutoBackupEnabled = 'auto_backup_enabled';
const _prefAutoBackupInterval = 'auto_backup_interval';

// ── Exported value objects ─────────────────────────────────────────────────

class BackupLockoutException implements Exception {
  final int minutesRemaining;
  const BackupLockoutException(this.minutesRemaining);

  @override
  String toString() =>
      'Too many failed attempts. Try again in $minutesRemaining minutes.';
}

class BackupAuthException implements Exception {
  const BackupAuthException();

  @override
  String toString() => 'Incorrect passphrase. Please try again.';
}

class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);

  @override
  String toString() => message;
}

// ── Isolate helper for PBKDF2 ──────────────────────────────────────────────

/// Runs PBKDF2 in a background isolate to avoid blocking the UI.
Future<Uint8List> _derivePbkdf2({
  required String passphrase,
  required Uint8List salt,
}) {
  return compute(
    _pbkdf2Work,
    {'passphrase': passphrase, 'salt': salt},
  );
}

/// Top-level function required by [compute].
Uint8List _pbkdf2Work(Map<String, dynamic> args) {
  return _pbkdf2(
    args['passphrase'] as String,
    args['salt'] as Uint8List,
  );
}

/// Pure PBKDF2-HMAC-SHA256: one block (32-byte output) with 100k iterations.
Uint8List _pbkdf2(String passphrase, Uint8List salt) {
  final keyBytes = utf8.encode(passphrase);

  // Block 1: PRF(Password, Salt || INT(1))
  final seedData = Uint8List(salt.length + 4);
  seedData.setRange(0, salt.length, salt);
  // INT(1) as big-endian 4 bytes
  seedData[salt.length + 3] = 1;

  final hmac = Hmac(sha256, keyBytes);
  var u = Uint8List.fromList(hmac.convert(seedData).bytes);
  final result = Uint8List.fromList(u);

  for (var i = 1; i < _pbkdf2Iterations; i++) {
    u = Uint8List.fromList(Hmac(sha256, keyBytes).convert(u).bytes);
    for (var j = 0; j < 32; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

// ── Service ────────────────────────────────────────────────────────────────

class EncryptedBackupService {
  EncryptedBackupService._();
  static final EncryptedBackupService instance = EncryptedBackupService._();

  // ── Lockout helpers ───────────────────────────────────────────────────────

  /// True if currently in a lockout period (> 0 minutes remaining).
  Future<bool> isLockedOut() async {
    final prefs = await SharedPreferences.getInstance();
    final lockedUntil = prefs.getString(_prefLockedUntil);
    if (lockedUntil == null) return false;
    final until = DateTime.tryParse(lockedUntil);
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  /// Remaining minutes in the current lockout. 0 if not locked.
  Future<int> lockoutMinutesRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lockedUntil = prefs.getString(_prefLockedUntil);
    if (lockedUntil == null) return 0;
    final until = DateTime.tryParse(lockedUntil);
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inMinutes + 1;
  }

  /// Remaining passphrase attempts before lockout. 0 if locked.
  Future<int> attemptsRemaining() async {
    if (await isLockedOut()) return 0;
    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getInt(_prefAttempts) ?? 0;
    return (_maxAttempts - attempts).clamp(0, _maxAttempts);
  }

  Future<void> _recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_prefAttempts) ?? 0) + 1;
    await prefs.setInt(_prefAttempts, attempts);
    if (attempts >= _maxAttempts) {
      final lockUntil = DateTime.now().add(
        const Duration(minutes: _lockoutMinutes),
      );
      await prefs.setString(_prefLockedUntil, lockUntil.toIso8601String());
      await prefs.setInt(_prefAttempts, 0);
      debugPrint('[EncBackup] Locked out for $_lockoutMinutes minutes');
    }
  }

  Future<void> _clearFailures() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefAttempts);
    await prefs.remove(_prefLockedUntil);
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  /// Creates an encrypted `.kashcube` file in the app documents directory.
  ///
  /// Returns the [File] so the caller can share it via the OS share sheet.
  /// Throws [ArgumentError] if the passphrase is empty.
  Future<File> exportEncrypted(String passphrase) async {
    if (passphrase.isEmpty) {
      throw ArgumentError('Passphrase cannot be empty');
    }

    // 1. Generate random salt and IV
    final rng = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => rng.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => rng.nextInt(256)),
    );

    // 2. Derive AES-256 key via PBKDF2
    debugPrint('[EncBackup] Deriving key (PBKDF2, $_pbkdf2Iterations iters)…');
    final keyBytes = await _derivePbkdf2(passphrase: passphrase, salt: salt);

    // 3. Read the live DB file
    final dbPath = await getDatabasesPath();
    final dbFile = File(p.join(dbPath, AppConstants.dbName));
    if (!await dbFile.exists()) {
      throw const BackupFormatException('Database file not found');
    }
    final dbBytes = await dbFile.readAsBytes();

    // 4. Build manifest JSON
    final manifest = jsonEncode({
      'created_at': DateTime.now().toIso8601String(),
      'app_version': AppConstants.appVersion,
      'schema_version': AppConstants.dbVersion,
      'databases': [AppConstants.dbName],
    });
    final manifestBytes = Uint8List.fromList(utf8.encode(manifest));

    // 5. Build plaintext payload: [manifest_len(4)] + manifest + db_bytes
    final payloadLen = 4 + manifestBytes.length + dbBytes.length;
    final plaintext = ByteData(payloadLen);
    plaintext.setUint32(0, manifestBytes.length, Endian.big);
    final plaintextBytes = Uint8List(payloadLen)
      ..setRange(0, 4, plaintext.buffer.asUint8List())
      ..setRange(4, 4 + manifestBytes.length, manifestBytes)
      ..setRange(4 + manifestBytes.length, payloadLen, dbBytes);

    // 6. AES-256-GCM encrypt (auth tag appended by GCM to ciphertext)
    final aesKey = enc.Key(keyBytes);
    final aesIv = enc.IV(iv);
    final encrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encryptBytes(plaintextBytes, iv: aesIv);
    final ciphertextWithTag = encrypted.bytes;

    // 7. Assemble file bytes
    final magicBytes = utf8.encode(_magic);
    final totalLen = magicBytes.length + 1 + _saltLength + _ivLength +
        _schemaFieldLength + ciphertextWithTag.length;
    final output = BytesBuilder(copy: false);
    output.add(magicBytes);
    output.addByte(_fmtVersion);
    output.add(salt);
    output.add(iv);
    // Schema version (4 bytes big-endian, unencrypted — for migration preview)
    final schemaBuf = ByteData(4)
      ..setUint32(0, AppConstants.dbVersion, Endian.big);
    output.add(schemaBuf.buffer.asUint8List());
    output.add(ciphertextWithTag);

    debugPrint('[EncBackup] Assembled file: $totalLen bytes');

    // 8. Write to exports/ subdir (excluded from Android Auto Backup)
    final appDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(appDir.path, 'exports'));
    await exportsDir.create(recursive: true);
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final outFile = File(p.join(exportsDir.path, 'kash_cube_$timestamp.kashcube'));
    await outFile.writeAsBytes(output.takeBytes());

    // Record last backup date
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefLastBackupDate, DateTime.now().toIso8601String());
    debugPrint('[EncBackup] Exported to ${outFile.path}');
    return outFile;
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Imports and restores a `.kashcube` backup.
  ///
  /// Steps:
  ///   1. Validate magic bytes and format version.
  ///   2. Check lockout.
  ///   3. Derive AES key from passphrase + stored salt.
  ///   4. AES-256-GCM decrypt — throws [BackupAuthException] on auth failure.
  ///   5. Parse manifest, copy decrypted DB to live path.
  ///
  /// The caller must restart the app (or re-open the DB) after restore.
  Future<Map<String, dynamic>> importEncrypted(
      String filePath, String passphrase) async {
    // ── Lockout check ──────────────────────────────────────────────────────
    if (await isLockedOut()) {
      final mins = await lockoutMinutesRemaining();
      throw BackupLockoutException(mins);
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw const BackupFormatException('Backup file not found');
    }
    final bytes = await file.readAsBytes();

    // ── Validate header ────────────────────────────────────────────────────
    if (bytes.length < 4 + 1 + _saltLength + _ivLength + _schemaFieldLength) {
      throw const BackupFormatException('File is too small — not a valid .kashcube file');
    }

    final magic = utf8.decode(bytes.sublist(0, 4));
    if (magic != _magic) {
      throw const BackupFormatException('Not a valid Kash Cube backup file');
    }

    final version = bytes[4];
    if (version != _fmtVersion) {
      throw BackupFormatException('Unsupported backup format version: $version');
    }

    var offset = 5;
    final salt = bytes.sublist(offset, offset + _saltLength);
    offset += _saltLength;

    final iv = bytes.sublist(offset, offset + _ivLength);
    offset += _ivLength;

    final schemaBuf = ByteData.sublistView(
        Uint8List.fromList(bytes.sublist(offset, offset + _schemaFieldLength)));
    final fileSchemaVersion = schemaBuf.getUint32(0, Endian.big);
    offset += _schemaFieldLength;

    final ciphertextWithTag = bytes.sublist(offset);

    debugPrint('[EncBackup] File schema: $fileSchemaVersion, current: ${AppConstants.dbVersion}');

    // ── Derive key & decrypt ───────────────────────────────────────────────
    debugPrint('[EncBackup] Deriving key for import…');
    final keyBytes = await _derivePbkdf2(
      passphrase: passphrase,
      salt: Uint8List.fromList(salt),
    );

    List<int> plaintext;
    try {
      final aesKey = enc.Key(Uint8List.fromList(keyBytes));
      final aesIv = enc.IV(Uint8List.fromList(iv));
      final encrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.gcm));
      plaintext =
          encrypter.decryptBytes(enc.Encrypted(Uint8List.fromList(ciphertextWithTag)), iv: aesIv);
    } catch (_) {
      await _recordFailure();
      throw const BackupAuthException();
    }

    // ── Parse manifest ─────────────────────────────────────────────────────
    final manifestLen = ByteData.sublistView(
            Uint8List.fromList(plaintext.sublist(0, 4)))
        .getUint32(0, Endian.big);
    final manifestJson =
        utf8.decode(plaintext.sublist(4, 4 + manifestLen));
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    final dbBytes = Uint8List.fromList(
        plaintext.sublist(4 + manifestLen));

    // ── Restore to DB path ─────────────────────────────────────────────────
    final dbPath = await getDatabasesPath();
    final livePath = p.join(dbPath, AppConstants.dbName);

    // Back up current DB before overwrite
    final prevPath = p.join(dbPath, 'kash_cube_before_restore.db');
    final liveFile = File(livePath);
    if (await liveFile.exists()) {
      await liveFile.copy(prevPath);
      debugPrint('[EncBackup] Pre-restore snapshot → $prevPath');
    }

    await File(livePath).writeAsBytes(dbBytes);
    await _clearFailures();
    debugPrint('[EncBackup] Restored ${dbBytes.length} bytes from backup');

    return manifest;
  }

  // ── Last backup date ───────────────────────────────────────────────────────

  /// ISO-8601 string of the last encrypted backup date, or null if never.
  Future<DateTime?> lastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefLastBackupDate);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Number of days since the last encrypted backup. null if never backed up.
  Future<int?> daysSinceLastBackup() async {
    final last = await lastBackupDate();
    if (last == null) return null;
    return DateTime.now().difference(last).inDays;
  }

  // ── Auto-backup preferences ───────────────────────────────────────────────

  /// Whether automatic periodic backup is enabled.
  Future<bool> autoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoBackupEnabled) ?? false;
  }

  /// Enable or disable automatic periodic backup.
  Future<void> setAutoBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoBackupEnabled, value);
  }

  /// Backup interval string: 'daily', 'weekly' (default), or 'monthly'.
  Future<String> autoBackupInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefAutoBackupInterval) ?? 'weekly';
  }

  /// Persist the backup interval choice ('daily', 'weekly', 'monthly').
  Future<void> setAutoBackupInterval(String interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAutoBackupInterval, interval);
  }
}
