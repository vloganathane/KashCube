import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import 'sync_table_registry.dart';

/// Persisted sync progress metadata for one (peer, table) pair.
class SyncTableState {
  const SyncTableState({
    required this.peerIdentityId,
    required this.tableName,
    required this.syncMode,
    required this.schemaFingerprint,
    this.lastSyncedAt,
    this.lastVersion,
    this.lastPk,
    this.updatedAt,
  });

  final String peerIdentityId;
  final String tableName;
  final SyncMode syncMode;
  final String schemaFingerprint;
  final DateTime? lastSyncedAt;
  final int? lastVersion;
  final String? lastPk;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() {
    return {
      'peer_identity_id': peerIdentityId,
      'table_name': tableName,
      'sync_mode': syncMode.name,
      'last_synced_at': lastSyncedAt?.toUtc().toIso8601String(),
      'last_version': lastVersion,
      'last_pk': lastPk,
      'schema_fingerprint': schemaFingerprint,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static SyncTableState fromMap(Map<String, Object?> map) {
    final modeRaw = (map['sync_mode'] as String?) ?? SyncMode.snapshot.name;
    final mode = SyncMode.values.firstWhere(
      (m) => m.name == modeRaw,
      orElse: () => SyncMode.snapshot,
    );

    return SyncTableState(
      peerIdentityId: (map['peer_identity_id'] as String?) ?? '',
      tableName: (map['table_name'] as String?) ?? '',
      syncMode: mode,
      schemaFingerprint: (map['schema_fingerprint'] as String?) ?? '',
      lastSyncedAt: DateTime.tryParse((map['last_synced_at'] as String?) ?? ''),
      lastVersion: map['last_version'] as int?,
      lastPk: map['last_pk'] as String?,
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? ''),
    );
  }
}

/// Storage helper for `sync_table_state` metadata.
///
/// This is additive Phase 0 scaffolding; call sites are introduced in later phases.
class SyncTableStateStore {
  SyncTableStateStore._();
  static final SyncTableStateStore instance = SyncTableStateStore._();

  static const _table = 'sync_table_state';

  Future<SyncTableState?> read({
    required String peerIdentityId,
    required String tableName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      _table,
      where: 'peer_identity_id = ? AND table_name = ?',
      whereArgs: [peerIdentityId, tableName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncTableState.fromMap(rows.first);
  }

  Future<List<SyncTableState>> readAllForPeer(String peerIdentityId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      _table,
      where: 'peer_identity_id = ?',
      whereArgs: [peerIdentityId],
      orderBy: 'table_name ASC',
    );
    return rows.map(SyncTableState.fromMap).toList();
  }

  Future<void> upsert(SyncTableState state) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      _table,
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateProgress({
    required String peerIdentityId,
    required String tableName,
    required SyncMode syncMode,
    required String schemaFingerprint,
    DateTime? lastSyncedAt,
    int? lastVersion,
    String? lastPk,
  }) async {
    await upsert(
      SyncTableState(
        peerIdentityId: peerIdentityId,
        tableName: tableName,
        syncMode: syncMode,
        schemaFingerprint: schemaFingerprint,
        lastSyncedAt: lastSyncedAt,
        lastVersion: lastVersion,
        lastPk: lastPk,
      ),
    );
  }

  /// Resets cursor/watermark fields when table schema fingerprint changes.
  Future<void> resetIfSchemaChanged({
    required String peerIdentityId,
    required String tableName,
    required SyncMode syncMode,
    required String schemaFingerprint,
  }) async {
    final existing = await read(
      peerIdentityId: peerIdentityId,
      tableName: tableName,
    );

    if (existing == null || existing.schemaFingerprint == schemaFingerprint) {
      return;
    }

    await upsert(
      SyncTableState(
        peerIdentityId: peerIdentityId,
        tableName: tableName,
        syncMode: syncMode,
        schemaFingerprint: schemaFingerprint,
        lastSyncedAt: null,
        lastVersion: null,
        lastPk: null,
      ),
    );
  }

  Future<void> clearPeer(String peerIdentityId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      _table,
      where: 'peer_identity_id = ?',
      whereArgs: [peerIdentityId],
    );
  }

  Future<void> clearTable(String tableName) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(_table, where: 'table_name = ?', whereArgs: [tableName]);
  }
}
