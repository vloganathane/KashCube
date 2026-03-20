import 'package:sqflite/sqflite.dart';

/// Generic sync mode selected from table schema.
enum SyncMode {
  deltaTs,
  deltaVersion,
  snapshot,
}

/// Controls which sync channels a table participates in.
enum SyncScope {
  /// Syncs over both P2P (phone↔phone) and Web Companion (phone↔browser).
  all,

  /// Syncs to the Web Companion only.
  ///
  /// Excluded from P2P because the data is already embedded on every phone
  /// (e.g. [hsn_master]) or because bandwidth cost outweighs the benefit.
  webOnly,

  /// Phone is the authoritative master; excluded from all sync channels.
  ///
  /// Differs from [localOnly] in that the exclusion is architectural rather
  /// than a security requirement — these tables need a dedicated merge
  /// strategy (e.g. max-wins for sequence counters) that LWW cannot provide.
  phoneOnly,

  /// Must never leave this device.
  ///
  /// Contains cryptographic key material, device-specific identity/session
  /// state, or sync-engine internal metadata.
  localOnly,
}

/// Runtime sync plan for a single table discovered from SQLite schema.
class SyncTablePlan {
  const SyncTablePlan({
    required this.tableName,
    required this.mode,
    required this.scope,
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

  /// Which sync channels this table participates in.
  final SyncScope scope;

  final String? keyColumn;
  final bool hasCreatedAt;
  final bool hasUpdatedAt;
  final bool hasDeletedAt;
  final bool hasVersion;
  final String schemaFingerprint;
  final Set<String> columns;

  /// True when this table should be included in P2P (phone↔phone) sync.
  bool get isP2pEligible => scope == SyncScope.all;

  /// True when this table should be included in Web Companion (phone↔browser) sync.
  bool get isWebEligible =>
      scope == SyncScope.all || scope == SyncScope.webOnly;
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

  // ── Scope tables ──────────────────────────────────────────────────────────

  /// Tables that must NEVER leave this device (completely excluded from discovery).
  ///
  /// Contains cryptographic key material (Ed25519), P2P pairing secrets,
  /// sync-engine internal state, and device-local notification queues.
  static const Set<String> _localOnlyTables = {
    // Sync / P2P engine internals
    'device_session',
    'device_recovery',
    'pairing_history',
    'trusted_peers',
    'sync_outbox',
    'sync_watermarks',
    'sync_table_state',
    'schema_version',
    // Ed25519 private key material — absolutely must not leave the device.
    'my_identity',
    'linked_devices',
    'linked_business_sessions',
    // Device-local notification delivery state
    'payroll_notifications',
  };

  /// Tables excluded from all sync because the phone is the authoritative
  /// master and LWW merge is unsafe (e.g. sequence counters).
  static const Set<String> _phoneOnlyTables = {
    // Invoice number sequences — LWW would corrupt numbering on both sides.
    'invoice_number_cursors',
  };

  /// Tables excluded from P2P but included in Web Companion sync.
  ///
  /// [hsn_master] is already embedded on every phone (seeded from assets),
  /// so P2P would just duplicate it — but the browser needs a copy to render
  /// HSN code pickers for invoice creation.
  static const Set<String> _webOnlyTables = {
    'hsn_master',
  };

  // Tables previously in the blanket denylist that are now fully syncable:
  //   app_users, user_permissions — RBAC; browser enforces the same rules.
  //   subscription, plan_features — feature gates; all devices must agree.

  Future<List<SyncTablePlan>> discoverSyncPlans(
    Database db, {
    Set<String> extraDenylist = const {},
  }) async {
    // Only localOnly tables are fully excluded from discovery.
    // phoneOnly and webOnly tables are discovered and assigned their scope.
    final excluded = <String>{..._localOnlyTables, ...extraDenylist};

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
      if (excluded.contains(tableName)) continue;

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

    final scope = _phoneOnlyTables.contains(tableName)
        ? SyncScope.phoneOnly
        : _webOnlyTables.contains(tableName)
            ? SyncScope.webOnly
            : SyncScope.all;

    final schemaFingerprint = _schemaFingerprint(tableName, columns);

    return SyncTablePlan(
      tableName: tableName,
      mode: mode,
      scope: scope,
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
