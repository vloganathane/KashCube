import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/sync_table_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<Database> _openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      // deltaTs table — updated_at + created_at
      await db.execute('''
        CREATE TABLE invoices (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_id    TEXT UNIQUE,
          updated_at TEXT,
          created_at TEXT,
          deleted_at TEXT
        )
      ''');

      // deltaVersion table — version only, no timestamp
      await db.execute('''
        CREATE TABLE settings (
          key     TEXT PRIMARY KEY,
          value   TEXT,
          version INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // snapshot table — neither timestamp nor version
      await db.execute('''
        CREATE TABLE hsn_master (
          hsn_code TEXT PRIMARY KEY,
          description TEXT
        )
      ''');

      // phoneOnly table (in _phoneOnlyTables)
      await db.execute('''
        CREATE TABLE invoice_number_cursors (
          id  INTEGER PRIMARY KEY,
          seq INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // localOnly table — should be EXCLUDED from discovery
      await db.execute('''
        CREATE TABLE my_identity (
          id         INTEGER PRIMARY KEY,
          private_key TEXT
        )
      ''');

      // A generic table with only created_at (no updated_at)
      await db.execute('''
        CREATE TABLE audit_log (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_id    TEXT UNIQUE,
          created_at TEXT,
          deleted_at TEXT
        )
      ''');
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Database db;

  setUpAll(() async {
    db = await _openTestDb();
  });

  tearDownAll(() async => db.close());

  Future<Map<String, SyncTablePlan>> plansMap() async {
    SyncTableRegistry.instance.clearCache();
    final all = await SyncTableRegistry.instance.discoverSyncPlans(db);
    return {for (final p in all) p.tableName: p};
  }

  // ── Scope assignment ──────────────────────────────────────────────────────

  group('SyncScope assignment', () {
    test('regular table gets SyncScope.all', () async {
      final plans = await plansMap();
      expect(plans['invoices']?.scope, SyncScope.all);
    });

    test('phoneOnly table gets SyncScope.phoneOnly', () async {
      final plans = await plansMap();
      expect(plans['invoice_number_cursors']?.scope, SyncScope.phoneOnly);
    });

    test('webOnly table gets SyncScope.webOnly', () async {
      final plans = await plansMap();
      expect(plans['hsn_master']?.scope, SyncScope.webOnly);
    });

    test('localOnly table is excluded entirely', () async {
      final plans = await plansMap();
      expect(plans.containsKey('my_identity'), isFalse);
    });
  });

  // ── Mode selection ────────────────────────────────────────────────────────

  group('SyncMode selection', () {
    test('updated_at table ⟹ deltaTs', () async {
      final plans = await plansMap();
      expect(plans['invoices']?.mode, SyncMode.deltaTs);
    });

    test('created_at-only table ⟹ deltaTs', () async {
      final plans = await plansMap();
      expect(plans['audit_log']?.mode, SyncMode.deltaTs);
    });

    test('version-only table ⟹ deltaVersion', () async {
      final plans = await plansMap();
      expect(plans['settings']?.mode, SyncMode.deltaVersion);
    });

    test('table with neither timestamp nor version ⟹ snapshot', () async {
      final plans = await plansMap();
      expect(plans['hsn_master']?.mode, SyncMode.snapshot);
    });
  });

  // ── isP2pEligible / isWebEligible ─────────────────────────────────────────

  group('eligibility helpers', () {
    test('SyncScope.all ⟹ P2P-eligible AND web-eligible', () async {
      final plans = await plansMap();
      final p = plans['invoices']!;
      expect(p.isP2pEligible, isTrue);
      expect(p.isWebEligible, isTrue);
    });

    test('SyncScope.webOnly ⟹ NOT P2P-eligible but web-eligible', () async {
      final plans = await plansMap();
      final p = plans['hsn_master']!;
      expect(p.isP2pEligible, isFalse);
      expect(p.isWebEligible, isTrue);
    });

    test('SyncScope.phoneOnly ⟹ NOT P2P-eligible, NOT web-eligible', () async {
      final plans = await plansMap();
      final p = plans['invoice_number_cursors']!;
      expect(p.isP2pEligible, isFalse);
      expect(p.isWebEligible, isFalse);
    });
  });

  // ── keyColumn detection ───────────────────────────────────────────────────

  group('keyColumn detection', () {
    test('prefers sync_id over id', () async {
      final plans = await plansMap();
      expect(plans['invoices']?.keyColumn, 'sync_id');
    });

    test('falls back to id when no sync_id', () async {
      final plans = await plansMap();
      // invoice_number_cursors has id but no sync_id
      expect(plans['invoice_number_cursors']?.keyColumn, 'id');
    });

    test('falls back to SQLite PK text column when no sync_id/id', () async {
      final plans = await plansMap();
      // settings table: PK is 'key'
      expect(plans['settings']?.keyColumn, 'key');
    });
  });

  // ── extraDenylist ─────────────────────────────────────────────────────────

  group('extraDenylist', () {
    test('explicitly denied table is excluded', () async {
      SyncTableRegistry.instance.clearCache();
      final plans = await SyncTableRegistry.instance.discoverSyncPlans(
        db,
        extraDenylist: {'audit_log'},
      );
      final names = plans.map((p) => p.tableName).toSet();
      expect(names, isNot(contains('audit_log')));
    });
  });

  // ── column flags ──────────────────────────────────────────────────────────

  group('column flags', () {
    test('hasUpdatedAt, hasCreatedAt, hasDeletedAt for invoices', () async {
      final plans = await plansMap();
      final p = plans['invoices']!;
      expect(p.hasUpdatedAt, isTrue);
      expect(p.hasCreatedAt, isTrue);
      expect(p.hasDeletedAt, isTrue);
    });

    test('created_at-only table', () async {
      final plans = await plansMap();
      final p = plans['audit_log']!;
      expect(p.hasUpdatedAt, isFalse);
      expect(p.hasCreatedAt, isTrue);
    });
  });
}
