import 'package:sqflite/sqflite.dart';

import '../../data/models/linked_device.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/linked_device_repository.dart';

/// SQLite implementation of [LinkedDeviceRepository].
/// Uses the `linked_devices` table (schema version 8+).
class LinkedDeviceRepositoryImpl implements LinkedDeviceRepository {
  LinkedDeviceRepositoryImpl([DatabaseHelper? db])
      : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  static const _table = 'linked_devices';

  @override
  Future<List<LinkedDevice>> getAll() => _db.withDatabase((db) async {
        final rows = await db.query(_table, orderBy: 'created_at DESC');
        return rows.map(LinkedDevice.fromMap).toList();
      });

  @override
  Future<List<LinkedDevice>> getActive() => _db.withDatabase((db) async {
        final rows = await db.query(
          _table,
          where:     'revoked_at IS NULL',
          orderBy:   'created_at DESC',
        );
        return rows.map(LinkedDevice.fromMap).toList();
      });

  @override
  Future<LinkedDevice?> getByDeviceId(String deviceId) =>
      _db.withDatabase((db) async {
        final rows = await db.query(
          _table,
          where:     'device_id = ?',
          whereArgs: [deviceId],
          limit:     1,
        );
        if (rows.isEmpty) return null;
        return LinkedDevice.fromMap(rows.first);
      });

  @override
  Future<void> insert(LinkedDevice device) => _db.withDatabase((db) async {
        await db.insert(
          _table,
          {
            'sync_id':             device.syncId,
            'device_id':           device.deviceId,
            'device_name':         device.deviceName,
            if (device.deviceType != null) 'device_type': device.deviceType,
            if (device.deviceOs   != null) 'device_os':   device.deviceOs,
            'secondary_public_key': device.secondaryPublicKey,
            if (device.userId        != null) 'user_id':         device.userId,
            if (device.linkedPartyId != null) 'linked_party_id': device.linkedPartyId,
            'permission_scope':    device.permissionScope,
            'business_scope':      device.businessScope,
            'offline_grace_days':  device.offlineGraceDays,
            'permission_preset':   device.preset.dbValue,
            if (device.secondaryIdentityId  != null) 'secondary_identity_id':  device.secondaryIdentityId,
            if (device.secondaryDisplayName != null) 'secondary_display_name': device.secondaryDisplayName,
            'created_at':          DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      });

  @override
  Future<void> update(LinkedDevice device) => _db.withDatabase((db) async {
        await db.update(
          _table,
          {
            'device_name':          device.deviceName,
            if (device.deviceType != null) 'device_type': device.deviceType,
            if (device.deviceOs   != null) 'device_os':   device.deviceOs,
            'permission_scope':     device.permissionScope,
            'business_scope':       device.businessScope,
            'offline_grace_days':   device.offlineGraceDays,
            'permission_preset':    device.preset.dbValue,
            if (device.lastSyncAt  != null)
              'last_sync_at': device.lastSyncAt!.toIso8601String(),
            if (device.revokedAt   != null)
              'revoked_at':   device.revokedAt!.toIso8601String(),
          },
          where:     'device_id = ?',
          whereArgs: [device.deviceId],
        );
      });

  @override
  Future<void> revoke(String deviceId) => _db.withDatabase((db) async {
        await db.update(
          _table,
          {'revoked_at': DateTime.now().toIso8601String()},
          where:     'device_id = ?',
          whereArgs: [deviceId],
        );
      });

  @override
  Future<void> updateLastSync(String deviceId, DateTime syncedAt) =>
      _db.withDatabase((db) async {
        await db.update(
          _table,
          {'last_sync_at': syncedAt.toIso8601String()},
          where:     'device_id = ?',
          whereArgs: [deviceId],
        );
      });

}
