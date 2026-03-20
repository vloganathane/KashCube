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
  // SQLite single-column PK detected from PRAGMA table_info (null for composite PKs).
  final Map<String, String?> _pkColumnCache = {};

  /// Tables that must NEVER leave this device.
  ///
  /// Includes engine metadata, device-specific identity/auth state, sequential
  /// number state (invoice cursors), local subscription flags, and reference
  /// data seeded from assets rather than user input.
  static const Set<String> _engineLocalDenylist = {
    // ── Engine / sync infrastructure ────────────────────────────────────
    'device_session',
    'device_recovery',
    'pairing_history',
    'trusted_peers',
    'sync_outbox',
    'sync_watermarks',
    'sync_table_state',
    'schema_version',
    // ── Device-local identity & auth ────────────────────────────────────
    // Contains Ed25519 key material — absolutely must not leave the device.
    'my_identity',
    'linked_devices',
    'linked_business_sessions',
    // ── Local access control ─────────────────────────────────────────────
    'app_users',
    'user_permissions',
    // ── Sequential counters (per-device state) ───────────────────────────
    // Syncing cursor rows would break invoice numbering on both sides.
    'invoice_number_cursors',
    // ── Subscription / feature flags (server-controlled) ────────────────
    'subscription',
    'plan_features',
    // ── Device-local notification state ─────────────────────────────────
    'payroll_notifications',
    // ── Reference / seed data (read-only, seeded from assets) ───────────
    'hsn_master',
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

      final pkColumn = _getPkColumn(tableName);
      plans.add(_buildPlan(tableName, columns, pkColumn));
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

    // Detect single-column primary key (pk > 0 marks PK columns).
    // Composite PKs are excluded (pkRows.length > 1) since no reliable generic merge.
    final pkRows = rows
        .where((r) => ((r['pk'] as num?)?.toInt() ?? 0) > 0)
        .toList()
      ..sort((a, b) =>
          ((a['pk'] as num).toInt()).compareTo((b['pk'] as num).toInt()));
    _pkColumnCache[tableName] = pkRows.length == 1
        ? (pkRows.first['name'] as String?)?.toLowerCase()
        : null;

    _columnsCache[tableName] = columns;
    return columns;
  }

  /// Returns the detected single-column primary key for [tableName],
  /// or null if the table has a composite PK or the cache is cold.
  String? _getPkColumn(String tableName) => _pkColumnCache[tableName];

  SyncTablePlan _buildPlan(String tableName, Set<String> columns, String? sqlitePkColumn) {
    final hasUpdatedAt = columns.contains('updated_at');
    final hasCreatedAt = columns.contains('created_at');
    final hasDeletedAt = columns.contains('deleted_at');
    final hasVersion = columns.contains('version');

    // Prefer explicit sync columns, then fall back to the actual SQLite PK.
    final keyColumn = columns.contains('sync_id')
        ? 'sync_id'
        : columns.contains('id')
            ? 'id'
            : sqlitePkColumn;

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

  void clearCache() {
    _columnsCache.clear();
    _pkColumnCache.clear();
  }
}
