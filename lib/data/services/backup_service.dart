import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../repositories/identity_repository_impl.dart';
import 'database_helper.dart';
import 'identity_service.dart';

/// Service for creating and restoring local database backups.
///
/// Backups are stored in the app's documents directory under `backups/`.
/// No data ever leaves the device.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _backupDir = 'backups';

  /// Returns the backup directory, creating it if needed.
  Future<Directory> _getBackupDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(join(appDir.path, _backupDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the path to the active database file.
  Future<String> _getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, AppConstants.dbName);
  }

  /// Create a backup of the current database.
  ///
  /// Returns the path to the backup file on success.
  Future<String> createBackup() async {
    try {
      // Close current DB connection to ensure all writes are flushed
      await DatabaseHelper.instance.close();

      final sourcePath = await _getDatabasePath();
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        throw Exception('Database file not found');
      }

      final backupDir = await _getBackupDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupName = 'kash_cube_backup_$timestamp.db';
      final backupPath = join(backupDir.path, backupName);

      await sourceFile.copy(backupPath);

      debugPrint('Backup created: $backupPath');
      return backupPath;
    } catch (e) {
      debugPrint('Backup failed: $e');
      rethrow;
    }
  }

  /// Restore database from a backup file.
  ///
  /// This replaces the current database with the backup.
  /// The app should restart after restore.
  Future<void> restoreFromBackup(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        throw Exception('Backup file not found');
      }

      // Close current DB connection
      await DatabaseHelper.instance.close();

      final dbPath = await _getDatabasePath();

      // Replace current DB with backup
      await backupFile.copy(dbPath);

      debugPrint('Database restored from: $backupPath');
    } catch (e) {
      debugPrint('Restore failed: $e');
      rethrow;
    }
  }

  /// List all available backup files, sorted newest first.
  Future<List<BackupInfo>> listBackups() async {
    final backupDir = await _getBackupDirectory();

    if (!await backupDir.exists()) return [];

    final files = await backupDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.db'))
        .map((entity) => entity as File)
        .toList();

    final backups = <BackupInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      backups.add(BackupInfo(
        path: file.path,
        name: basename(file.path),
        size: stat.size,
        createdAt: stat.modified,
      ));
    }

    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  /// Delete a backup file.
  Future<void> deleteBackup(String backupPath) async {
    final file = File(backupPath);
    if (await file.exists()) {
      await file.delete();
      debugPrint('Backup deleted: $backupPath');
    }
  }

  /// Get the total size of all backups in bytes.
  Future<int> getTotalBackupSize() async {
    final backups = await listBackups();
    var total = 0;
    for (final b in backups) {
      total += b.size;
    }
    return total;
  }

  // ── Identity section (v62+) ─────────────────────────────────────────────

  /// Exports the `my_identity` row and identity private-key seed as a JSON
  /// map suitable for embedding in a backup archive.
  ///
  /// Returns `null` when no identity has been set up yet.
  Future<Map<String, dynamic>?> exportIdentitySection() async {
    try {
      final identity = await IdentityRepositoryImpl().getMyIdentity();
      if (identity == null) return null;

      final privateSeed =
          await IdentityService.instance.exportIdentityPrivateKeySeed();

      return {
        'schema': 1,
        'identity_id':      identity.identityId,
        'display_name':     identity.displayName,
        'public_key':       identity.publicKey,
        'avatar_seed':      ?identity.avatarSeed,
        'created_at':       identity.createdAt.toIso8601String(),
        'private_key_seed': ?privateSeed,
      };
    } catch (e) {
      debugPrint('[BackupService] exportIdentitySection failed: $e');
      return null;
    }
  }

  /// Restores the identity from a JSON section previously produced by
  /// [exportIdentitySection].
  ///
  /// If [section] is `null` (old backup without identity), a fresh identity
  /// will be generated on the next app start via [IdentitySetupScreen] or the
  /// silent init path.
  Future<void> importIdentitySection(Map<String, dynamic>? section) async {
    if (section == null) {
      // Old backup — clear any existing identity so fresh generation is triggered
      debugPrint('[BackupService] importIdentitySection: no identity section, will generate fresh identity');
      return;
    }

    try {
      final privateSeed = section['private_key_seed'] as String?;
      if (privateSeed != null) {
        await IdentityService.instance.importIdentityPrivateKeySeed(privateSeed);
      }

      final identityId  = section['identity_id']  as String?;
      final displayName = section['display_name'] as String?;
      final publicKey   = section['public_key']   as String?;

      if (identityId != null && displayName != null && publicKey != null) {
        await DatabaseHelper.instance.withDatabase((db) async {
          await db.delete('my_identity');
          await db.insert('my_identity', {
            'id':           1,
            'identity_id':  identityId,
            'display_name': displayName,
            'public_key':   publicKey,
            if (section['avatar_seed'] != null)
              'avatar_seed': section['avatar_seed'],
            if (section['created_at'] != null)
              'created_at': section['created_at'],
          });
        });
        debugPrint('[BackupService] importIdentitySection: restored identity $identityId');
      }
    } catch (e) {
      debugPrint('[BackupService] importIdentitySection failed: $e');
      rethrow;
    }
  }

  /// Serialises the identity section to a JSON string for inclusion in an
  /// encrypted backup archive (convenience wrapper).
  Future<String?> exportIdentityJson() async {
    final section = await exportIdentitySection();
    if (section == null) return null;
    return jsonEncode(section);
  }

  /// Deserialises and restores an identity section from a JSON string.
  Future<void> importIdentityJson(String? json) async {
    if (json == null || json.isEmpty) {
      return importIdentitySection(null);
    }
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      await importIdentitySection(map);
    } catch (e) {
      debugPrint('[BackupService] importIdentityJson parse error: $e');
      rethrow;
    }
  }
}

/// Information about a backup file.
class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.createdAt,
  });

  final String path;
  final String name;
  final int size;
  final DateTime createdAt;

  /// Human-readable file size.
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
