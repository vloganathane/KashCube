import 'package:sqflite/sqflite.dart';

/// Generic sync mode selected from table schema.
enum SyncMode {
  deltaTs,
  deltaVersion,
  snapshot,
}

/// Runtime sync plan for a single table discovered from SQLite schema.
class SyncTablePlan {
  const SyncTablePlan({
    required this.tableName,
    required this.mode,
    required this.keyColumn,
    required this.hasCreatedAt,
    required this.hasUpdatedAt,
    required this.hasDeletedAt,
    required this.hasVersion,
    required this.schemaFingerprint,
    required this.columns,
  });

  final String tableName;
  final SyncMode mode;
  final String? keyColumn;
  final bool hasCreatedAt;
  final bool hasUpdatedAt;
  final bool hasDeletedAt;
  final bool hasVersion;
  final String schemaFingerprint;
  final Set<String> columns;
}

/// Discovers syncable tables and derives generic sync plans.
///
/// This service is intentionally read-only in Phase 0.
class SyncTableRegistry {
  SyncTableRegistry._();
  static final SyncTableRegistry instance = SyncTableRegistry._();

  final Map<String, Set<String>> _columnsCache = {};

  static const Set<String> _engineLocalDenylist = {
    'device_session',
    'device_recovery',
    'pairing_history',
    'trusted_peers',
    'sync_outbox',
    'sync_watermarks',
    'sync_table_state',
  };

  Future<List<SyncTablePlan>> discoverSyncPlans(
    Database db, {
    Set<String> extraDenylist = const {},
  }) async {
    final denylist = <String>{..._engineLocalDenylist, ...extraDenylist};

    final tableRows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    ''');

    final plans = <SyncTablePlan>[];
    for (final row in tableRows) {
      final tableName = (row['name'] as String?)?.trim();
      if (tableName == null || tableName.isEmpty) continue;
      if (denylist.contains(tableName)) continue;

      final columns = await _getTableColumns(db, tableName);
      if (columns.isEmpty) continue;

      plans.add(_buildPlan(tableName, columns));
    }

    plans.sort((a, b) => a.tableName.compareTo(b.tableName));
    return plans;
  }

  Future<Set<String>> _getTableColumns(Database db, String tableName) async {
    final cached = _columnsCache[tableName];
    if (cached != null) return cached;

    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = rows
        .map((r) => (r['name'] as String?)?.toLowerCase())
        .whereType<String>()
        .toSet();

    _columnsCache[tableName] = columns;
    return columns;
  }

  SyncTablePlan _buildPlan(String tableName, Set<String> columns) {
    final hasUpdatedAt = columns.contains('updated_at');
    final hasCreatedAt = columns.contains('created_at');
    final hasDeletedAt = columns.contains('deleted_at');
    final hasVersion = columns.contains('version');

    final keyColumn = columns.contains('sync_id')
        ? 'sync_id'
        : columns.contains('id')
            ? 'id'
            : null;

    final mode = (hasUpdatedAt || hasCreatedAt)
        ? SyncMode.deltaTs
        : hasVersion
            ? SyncMode.deltaVersion
            : SyncMode.snapshot;

    final schemaFingerprint = _schemaFingerprint(tableName, columns);

    return SyncTablePlan(
      tableName: tableName,
      mode: mode,
      keyColumn: keyColumn,
      hasCreatedAt: hasCreatedAt,
      hasUpdatedAt: hasUpdatedAt,
      hasDeletedAt: hasDeletedAt,
      hasVersion: hasVersion,
      schemaFingerprint: schemaFingerprint,
      columns: columns,
    );
  }

  String _schemaFingerprint(String tableName, Set<String> columns) {
    final sortedColumns = columns.toList()..sort();
    return '$tableName|${sortedColumns.join(',')}';
  }

  void clearCache() => _columnsCache.clear();
}
