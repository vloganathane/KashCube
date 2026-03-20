import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/generic_sync_query_builder.dart';
import 'package:kash_cube/data/services/sync/sync_table_registry.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

SyncTablePlan _deltaTs({
  String table = 'invoices',
  bool hasUpdatedAt = true,
  bool hasCreatedAt = true,
  bool hasDeletedAt = true,
  String? keyColumn = 'sync_id',
  SyncScope scope = SyncScope.all,
}) =>
    SyncTablePlan(
      tableName:         table,
      mode:              SyncMode.deltaTs,
      keyColumn:         keyColumn,
      hasUpdatedAt:      hasUpdatedAt,
      hasCreatedAt:      hasCreatedAt,
      hasDeletedAt:      hasDeletedAt,
      hasVersion:        false,
      scope:             scope,
      schemaFingerprint: '$table:test',
      columns:           const {},
    );

SyncTablePlan _deltaVersion({
  String table = 'settings',
  bool hasDeletedAt = false,
  String? keyColumn = 'key',
}) =>
    SyncTablePlan(
      tableName:         table,
      mode:              SyncMode.deltaVersion,
      keyColumn:         keyColumn,
      hasUpdatedAt:      false,
      hasCreatedAt:      false,
      hasDeletedAt:      hasDeletedAt,
      hasVersion:        true,
      scope:             SyncScope.all,
      schemaFingerprint: '$table:test',
      columns:           const {},
    );

SyncTablePlan _snapshot({
  String table = 'hsn_master',
  bool hasDeletedAt = false,
  String? keyColumn = 'hsn_code',
}) =>
    SyncTablePlan(
      tableName:         table,
      mode:              SyncMode.snapshot,
      keyColumn:         keyColumn,
      hasUpdatedAt:      false,
      hasCreatedAt:      false,
      hasDeletedAt:      hasDeletedAt,
      hasVersion:        false,
      scope:             SyncScope.webOnly,
      schemaFingerprint: '$table:test',
      columns:           const {},
    );

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('GenericSyncQueryBuilder.buildOutboundQuery', () {
    // ── deltaTs ──────────────────────────────────────────────────────────────

    group('deltaTs', () {
      test('full scan when since is null', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaTs(),
        );
        expect(q.args, isEmpty);
        expect(q.sql, contains('SELECT * FROM invoices'));
        expect(q.sql, isNot(contains('julianday(?)')));
        expect(q.sql, contains('deleted_at IS NULL'));
        expect(q.sql, contains('ORDER BY'));
        expect(q.sql, contains('LIMIT 200'));
      });

      test('incremental query with since', () {
        final since = DateTime.utc(2025, 6, 1, 12, 0, 0);
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaTs(),
          since: since,
        );
        expect(q.args, hasLength(1));
        expect(q.args.first, since.toIso8601String());
        expect(q.sql, contains('julianday(?)'));
        expect(q.sql, contains('COALESCE(updated_at, created_at)'));
        expect(q.sql, contains('deleted_at IS NULL'));
      });

      test('created_at-only table uses created_at (not updated_at column)', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaTs(hasUpdatedAt: false, hasCreatedAt: true),
          since: DateTime.utc(2025, 1, 1),
        );
        expect(q.sql, contains('created_at'));
        expect(q.sql, isNot(contains('updated_at')));
        expect(q.sql, isNot(contains('COALESCE')));
      });

      test('updated_at-only table uses updated_at', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaTs(hasUpdatedAt: true, hasCreatedAt: false),
          since: DateTime.utc(2025, 1, 1),
        );
        expect(q.sql, contains('updated_at'));
        expect(q.sql, isNot(contains('COALESCE')));
      });

      test('no timestamp columns ⟹ no WHERE ts clause (safe full scan)', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaTs(hasUpdatedAt: false, hasCreatedAt: false),
          since: DateTime.utc(2025, 1, 1),
        );
        // since is provided but there are no columns to filter on
        expect(q.args, isEmpty,
            reason: 'no column to bind the since arg to');
        expect(q.sql, isNot(contains('julianday(?)')));
      });

      test('no deleted_at column ⟹ no soft-delete filter', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaTs(hasDeletedAt: false),
        );
        expect(q.sql, isNot(contains('deleted_at')));
      });

      test('custom limit is respected', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan:  _deltaTs(),
          limit: 500,
        );
        expect(q.sql, contains('LIMIT 500'));
      });

      test('UTC normalisation uses julianday + LIKE %Z guard', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan:  _deltaTs(),
          since: DateTime.utc(2025, 1, 1),
        );
        expect(q.sql, contains("LIKE '%Z'"));
        expect(q.sql, contains("julianday(COALESCE(updated_at, created_at), 'utc')"));
      });
    });

    // ── deltaVersion ─────────────────────────────────────────────────────────

    group('deltaVersion', () {
      test('full scan when afterVersion is null', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaVersion(),
        );
        expect(q.args, isEmpty);
        expect(q.sql, contains('SELECT * FROM settings'));
        expect(q.sql, isNot(contains('version > ?')));
        expect(q.sql, contains('ORDER BY version ASC'));
      });

      test('incremental query with afterVersion', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan:         _deltaVersion(),
          afterVersion: 42,
        );
        expect(q.args, equals([42]));
        expect(q.sql, contains('version > ?'));
        expect(q.sql, contains('ORDER BY version ASC'));
      });

      test('soft-delete filter applied when hasDeletedAt=true', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _deltaVersion(hasDeletedAt: true),
        );
        expect(q.sql, contains('deleted_at IS NULL'));
      });

      test('limit is respected', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan:  _deltaVersion(),
          limit: 50,
        );
        expect(q.sql, contains('LIMIT 50'));
      });
    });

    // ── snapshot ─────────────────────────────────────────────────────────────

    group('snapshot', () {
      test('returns full scan with no args', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _snapshot(),
        );
        expect(q.args, isEmpty);
        expect(q.sql, contains('SELECT * FROM hsn_master'));
        expect(q.sql, isNot(contains('WHERE')));
        expect(q.sql, contains('ORDER BY hsn_code ASC'));
        expect(q.sql, contains('LIMIT 200'));
      });

      test('soft-delete filter applied when hasDeletedAt=true', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _snapshot(hasDeletedAt: true),
        );
        expect(q.sql, contains('deleted_at IS NULL'));
      });

      test('no ORDER BY when keyColumn is null', () {
        final q = GenericSyncQueryBuilder.buildOutboundQuery(
          plan: _snapshot(keyColumn: null),
        );
        expect(q.sql, isNot(contains('ORDER BY')));
      });
    });
  });

  // ── utcExpr ────────────────────────────────────────────────────────────────

  group('GenericSyncQueryBuilder.utcExpr', () {
    test('wraps a column correctly', () {
      final expr = GenericSyncQueryBuilder.utcExpr('updated_at');
      expect(expr, contains("LIKE '%Z'"));
      expect(expr, contains('julianday(updated_at)'));
      expect(expr, contains("julianday(updated_at, 'utc')"));
    });
  });

  // ── maxTimestamp ───────────────────────────────────────────────────────────

  group('GenericSyncQueryBuilder.maxTimestamp', () {
    test('returns epoch for empty list', () {
      final ts = GenericSyncQueryBuilder.maxTimestamp([]);
      expect(ts, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });

    test('picks updated_at over created_at', () {
      final rows = [
        {'updated_at': '2025-06-01T10:00:00.000Z', 'created_at': '2025-01-01T00:00:00.000Z'},
        {'updated_at': '2025-07-15T08:30:00.000Z', 'created_at': '2025-01-02T00:00:00.000Z'},
      ];
      final ts = GenericSyncQueryBuilder.maxTimestamp(rows);
      expect(ts, DateTime.utc(2025, 7, 15, 8, 30));
    });

    test('falls back to created_at when updated_at absent', () {
      final rows = [
        {'created_at': '2025-05-20T12:00:00.000Z'},
        {'created_at': '2025-05-21T09:00:00.000Z'},
      ];
      final ts = GenericSyncQueryBuilder.maxTimestamp(rows);
      expect(ts, DateTime.utc(2025, 5, 21, 9, 0));
    });

    test('ignores rows with no parseable timestamp', () {
      final rows = [
        {'name': 'foo'},
        {'updated_at': '2025-03-01T00:00:00.000Z'},
      ];
      final ts = GenericSyncQueryBuilder.maxTimestamp(rows);
      expect(ts, DateTime.utc(2025, 3, 1));
    });
  });

  // ── maxVersion ────────────────────────────────────────────────────────────

  group('GenericSyncQueryBuilder.maxVersion', () {
    test('returns null for empty list', () {
      expect(GenericSyncQueryBuilder.maxVersion([]), isNull);
    });

    test('returns max version across rows', () {
      final rows = [
        {'version': 3},
        {'version': 7},
        {'version': 5},
      ];
      expect(GenericSyncQueryBuilder.maxVersion(rows), 7);
    });

    test('ignores rows with null version', () {
      final rows = [
        {'version': null},
        {'version': 4},
      ];
      expect(GenericSyncQueryBuilder.maxVersion(rows), 4);
    });
  });
}
