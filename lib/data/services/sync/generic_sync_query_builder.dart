import 'sync_table_registry.dart';

/// Result of [GenericSyncQueryBuilder.buildOutboundQuery].
class SyncQuery {
  const SyncQuery({required this.sql, required this.args});

  final String sql;
  final List<Object?> args;
}

/// Builds mode-specific, fully-parameterised SQL for outbound sync queries.
///
/// All three [SyncMode]s are supported:
/// - [SyncMode.deltaTs]      — rows whose timestamp > [since].
/// - [SyncMode.deltaVersion] — rows whose [version] > [afterVersion].
/// - [SyncMode.snapshot]     — full table scan (no cursor needed).
///
/// The UTC normalisation expression is centralised here so all callers
/// (coordinator, web provider, session) use identical SQL.
class GenericSyncQueryBuilder {
  const GenericSyncQueryBuilder._();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Builds the outbound SELECT for [plan].
  ///
  /// [since]        — cursor for [SyncMode.deltaTs] (null → full scan).
  /// [afterVersion] — cursor for [SyncMode.deltaVersion] (null → full scan).
  /// [limit]        — row cap per batch (default 200).
  static SyncQuery buildOutboundQuery({
    required SyncTablePlan plan,
    DateTime? since,
    int? afterVersion,
    int limit = 200,
  }) {
    switch (plan.mode) {
      case SyncMode.deltaTs:
        return _buildDeltaTsQuery(plan, since, limit);
      case SyncMode.deltaVersion:
        return _buildDeltaVersionQuery(plan, afterVersion, limit);
      case SyncMode.snapshot:
        return _buildSnapshotQuery(plan, limit);
    }
  }

  // ── UTC expression ─────────────────────────────────────────────────────────

  /// Returns an SQLite expression that converts [col] to a Julian Day number,
  /// normalising both UTC-suffixed ISO strings and bare ISO strings uniformly.
  ///
  /// ```sql
  /// CASE WHEN col LIKE '%Z'
  ///   THEN julianday(col)
  ///   ELSE julianday(col, 'utc')
  /// END
  /// ```
  static String utcExpr(String col) =>
      "CASE WHEN $col LIKE '%Z' THEN julianday($col) ELSE julianday($col, 'utc') END";

  // ── Mode builders ──────────────────────────────────────────────────────────

  static SyncQuery _buildDeltaTsQuery(
    SyncTablePlan plan,
    DateTime? since,
    int limit,
  ) {
    final where = <String>[];
    final args = <Object?>[];

    if (since != null) {
      final sinceIso = since.toUtc().toIso8601String();

      if (plan.hasUpdatedAt && plan.hasCreatedAt) {
        where.add(
          "${utcExpr('COALESCE(updated_at, created_at)')} > julianday(?)",
        );
        args.add(sinceIso);
      } else if (plan.hasUpdatedAt) {
        where.add("${utcExpr('updated_at')} > julianday(?)");
        args.add(sinceIso);
      } else if (plan.hasCreatedAt) {
        where.add("${utcExpr('created_at')} > julianday(?)");
        args.add(sinceIso);
      }
      // If table has neither timestamp column, fall through to no cursor
      // (safe — returns all rows).
    }

    if (plan.hasDeletedAt) {
      where.add('deleted_at IS NULL');
    }

    final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    final orderBy = _tsOrderBy(plan);
    final sql = 'SELECT * FROM ${plan.tableName}$whereSql$orderBy LIMIT $limit';

    return SyncQuery(sql: sql, args: args);
  }

  static SyncQuery _buildDeltaVersionQuery(
    SyncTablePlan plan,
    int? afterVersion,
    int limit,
  ) {
    final where = <String>[];
    final args = <Object?>[];

    if (afterVersion != null) {
      where.add('version > ?');
      args.add(afterVersion);
    }

    if (plan.hasDeletedAt) {
      where.add('deleted_at IS NULL');
    }

    final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    final sql =
        'SELECT * FROM ${plan.tableName}$whereSql ORDER BY version ASC LIMIT $limit';

    return SyncQuery(sql: sql, args: args);
  }

  static SyncQuery _buildSnapshotQuery(SyncTablePlan plan, int limit) {
    final where = plan.hasDeletedAt ? ' WHERE deleted_at IS NULL' : '';
    final orderBy = plan.keyColumn != null
        ? ' ORDER BY ${plan.keyColumn} ASC'
        : '';
    final sql = 'SELECT * FROM ${plan.tableName}$where$orderBy LIMIT $limit';
    return SyncQuery(sql: sql, args: []);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _tsOrderBy(SyncTablePlan plan) {
    if (plan.hasUpdatedAt && plan.hasCreatedAt) {
      return " ORDER BY ${utcExpr('COALESCE(updated_at, created_at)')} ASC";
    }
    if (plan.hasUpdatedAt) return " ORDER BY ${utcExpr('updated_at')} ASC";
    if (plan.hasCreatedAt) return " ORDER BY ${utcExpr('created_at')} ASC";
    return '';
  }

  /// Extracts the latest timestamp from a batch of rows (used to advance the
  /// deltaTs watermark after a successful push).
  ///
  /// Returns the epoch if no timestamp is found (safe fallback — the next push
  /// will re-send all rows rather than silently drop them).
  static DateTime maxTimestamp(List<Map<String, dynamic>> rows) {
    var max = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final row in rows) {
      final ts =
          DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
          DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (ts != null && ts.toUtc().isAfter(max)) max = ts.toUtc();
    }
    return max;
  }

  /// Extracts the maximum `version` value from a batch of rows.
  static int? maxVersion(List<Map<String, dynamic>> rows) {
    int? max;
    for (final row in rows) {
      final v = (row['version'] as num?)?.toInt();
      if (v != null && (max == null || v > max)) max = v;
    }
    return max;
  }
}
