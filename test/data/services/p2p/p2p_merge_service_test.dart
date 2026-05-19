import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/p2p/p2p_merge_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<Database> _openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      // Minimal invoices table — only the columns the merge service touches.
      await db.execute('''
        CREATE TABLE invoices (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_id         TEXT    UNIQUE NOT NULL,
          status          TEXT    NOT NULL DEFAULT 'draft',
          updated_at      TEXT    NOT NULL,
          deleted_at      TEXT,
          version         INTEGER NOT NULL DEFAULT 0,
          updated_by_device_id TEXT,
          customer_name   TEXT    NOT NULL DEFAULT ''
        )
      ''');

      // Generic "parties" table — no special status column.
      await db.execute('''
        CREATE TABLE parties (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_id         TEXT    UNIQUE NOT NULL,
          name            TEXT    NOT NULL DEFAULT '',
          updated_at      TEXT    NOT NULL,
          deleted_at      TEXT,
          version         INTEGER NOT NULL DEFAULT 0,
          updated_by_device_id TEXT
        )
      ''');
    },
  );
  return db;
}

Map<String, dynamic> _invoice({
  required String syncId,
  required String status,
  required String updatedAt,
  String? deletedAt,
  int version = 0,
}) => {
  'sync_id': syncId,
  'status': status,
  'updated_at': updatedAt,
  'deleted_at': ?deletedAt,
  'version': version,
  'customer_name': 'Test Customer',
};

Map<String, dynamic> _party({
  required String syncId,
  required String name,
  required String updatedAt,
  String? deletedAt,
}) => {
  'sync_id': syncId,
  'name': name,
  'updated_at': updatedAt,
  'deleted_at': ?deletedAt,
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Database db;
  final merge = P2pMergeService.instance;
  const deviceId = 'local-device-id';

  setUp(() async => db = await _openTestDb());
  tearDown(() => db.close());

  // ── MergeResult helper ────────────────────────────────────────────────────

  group('MergeResult', () {
    test('total = inserted + updated + skipped', () {
      const r = MergeResult(table: 't', inserted: 2, updated: 3, skipped: 1);
      expect(r.total, 6);
    });

    test('hadChanges true when inserted > 0', () {
      const r = MergeResult(table: 't', inserted: 1, updated: 0, skipped: 0);
      expect(r.hadChanges, isTrue);
    });

    test('hadChanges true when updated > 0', () {
      const r = MergeResult(table: 't', inserted: 0, updated: 1, skipped: 0);
      expect(r.hadChanges, isTrue);
    });

    test('hadChanges false when only skipped', () {
      const r = MergeResult(table: 't', inserted: 0, updated: 0, skipped: 5);
      expect(r.hadChanges, isFalse);
    });
  });

  // ── LWW — generic table (parties) ────────────────────────────────────────

  group('LWW — generic table', () {
    test('inserts new row that does not exist locally', () async {
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          _party(
            syncId: 'p1',
            name: 'Ravi',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ),
        ],
      );
      expect(result.inserted, 1);
      expect(result.updated, 0);
      final row = (await db.query('parties', where: "sync_id = 'p1'")).first;
      expect(row['name'], 'Ravi');
      expect(row['updated_by_device_id'], deviceId);
    });

    test('updates local row when remote is newer', () async {
      await db.insert(
        'parties',
        _party(
          syncId: 'p2',
          name: 'Old',
          updatedAt: '2026-03-17T08:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          _party(
            syncId: 'p2',
            name: 'New',
            updatedAt: '2026-03-17T09:00:00.000Z',
          ),
        ],
      );
      expect(result.updated, 1);
      final row = (await db.query('parties', where: "sync_id = 'p2'")).first;
      expect(row['name'], 'New');
    });

    test('skips remote row when local is newer', () async {
      await db.insert(
        'parties',
        _party(
          syncId: 'p3',
          name: 'Newer',
          updatedAt: '2026-03-17T12:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          _party(
            syncId: 'p3',
            name: 'Older',
            updatedAt: '2026-03-17T08:00:00.000Z',
          ),
        ],
      );
      expect(result.skipped, 1);
      final row = (await db.query('parties', where: "sync_id = 'p3'")).first;
      expect(row['name'], 'Newer'); // not overwritten
    });

    test('skips row with null sync_id', () async {
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          {'name': 'Nobody', 'updated_at': '2026-03-17T10:00:00.000Z'},
        ],
      );
      expect(result.skipped, 1);
      expect((await db.query('parties')), isEmpty);
    });

    test('handles empty remote list gracefully', () async {
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [],
      );
      expect(result.inserted, 0);
      expect(result.updated, 0);
      expect(result.skipped, 0);
      expect(result.hadChanges, isFalse);
    });

    test('soft-delete: remote deleted_at wins when remote is newer', () async {
      await db.insert(
        'parties',
        _party(
          syncId: 'p4',
          name: 'Active',
          updatedAt: '2026-03-17T08:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          _party(
            syncId: 'p4',
            name: 'Active',
            updatedAt: '2026-03-17T09:00:00.000Z',
            deletedAt: '2026-03-17T09:00:00.000Z',
          ),
        ],
      );
      expect(result.updated, 1);
      final row = (await db.query('parties', where: "sync_id = 'p4'")).first;
      expect(row['deleted_at'], isNotNull);
    });

    test(
      'soft-delete: stale remote delete does NOT overwrite newer local',
      () async {
        await db.insert(
          'parties',
          _party(
            syncId: 'p5',
            name: 'Active',
            updatedAt: '2026-03-17T12:00:00.000Z',
          ),
        );
        final result = await merge.mergeTable(
          db: db,
          table: 'parties',
          deviceId: deviceId,
          remoteRows: [
            _party(
              syncId: 'p5',
              name: 'Active',
              updatedAt: '2026-03-17T08:00:00.000Z',
              deletedAt: '2026-03-17T08:00:00.000Z',
            ),
          ],
        );
        expect(result.skipped, 1);
        final row = (await db.query('parties', where: "sync_id = 'p5'")).first;
        expect(row['deleted_at'], isNull);
      },
    );
  });

  // ── Invoice state machine ─────────────────────────────────────────────────

  group('Invoice state machine', () {
    test('cancelled always wins over paid', () async {
      await db.insert(
        'invoices',
        _invoice(
          syncId: 'i1',
          status: 'paid',
          updatedAt: '2026-03-17T12:00:00.000Z', // local is NEWER
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i1',
            status: 'cancelled',
            updatedAt: '2026-03-17T08:00:00.000Z',
          ),
        ], // remote is OLDER
      );
      expect(result.updated, 1);
      final row = (await db.query('invoices', where: "sync_id = 'i1'")).first;
      expect(row['status'], 'cancelled');
    });

    test('paid beats partiallyPaid', () async {
      await db.insert(
        'invoices',
        _invoice(
          syncId: 'i2',
          status: 'partiallyPaid',
          updatedAt: '2026-03-17T12:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i2',
            status: 'paid',
            updatedAt: '2026-03-17T08:00:00.000Z',
          ),
        ],
      );
      expect(result.updated, 1);
      final row = (await db.query('invoices', where: "sync_id = 'i2'")).first;
      expect(row['status'], 'paid');
    });

    test('local cancelled blocks remote paid', () async {
      await db.insert(
        'invoices',
        _invoice(
          syncId: 'i3',
          status: 'cancelled',
          updatedAt: '2026-03-17T08:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i3',
            status: 'paid',
            updatedAt: '2026-03-17T12:00:00.000Z',
          ),
        ],
      );
      expect(result.skipped, 1);
      final row = (await db.query('invoices', where: "sync_id = 'i3'")).first;
      expect(row['status'], 'cancelled');
    });

    test('same status tier falls back to LWW — newer wins', () async {
      // 'sent' and 'overdue' are both tier 2; newer timestamp wins.
      await db.insert(
        'invoices',
        _invoice(
          syncId: 'i4',
          status: 'sent',
          updatedAt: '2026-03-17T08:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i4',
            status: 'overdue',
            updatedAt: '2026-03-17T12:00:00.000Z',
          ),
        ],
      );
      expect(result.updated, 1);
      final row = (await db.query('invoices', where: "sync_id = 'i4'")).first;
      expect(row['status'], 'overdue');
    });

    test('same status — LWW applies — older remote skipped', () async {
      await db.insert(
        'invoices',
        _invoice(
          syncId: 'i5',
          status: 'sent',
          updatedAt: '2026-03-17T12:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i5',
            status: 'sent',
            updatedAt: '2026-03-17T08:00:00.000Z',
          ),
        ],
      );
      expect(result.skipped, 1);
    });

    test('draft does not overwrite sent even if newer', () async {
      await db.insert(
        'invoices',
        _invoice(
          syncId: 'i6',
          status: 'sent',
          updatedAt: '2026-03-17T08:00:00.000Z',
        ),
      );
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i6',
            status: 'draft',
            updatedAt: '2026-03-17T12:00:00.000Z',
          ),
        ],
      );
      expect(result.skipped, 1);
      final row = (await db.query('invoices', where: "sync_id = 'i6'")).first;
      expect(row['status'], 'sent');
    });

    test('inserts new invoice with correct status', () async {
      final result = await merge.mergeTable(
        db: db,
        table: 'invoices',
        deviceId: deviceId,
        remoteRows: [
          _invoice(
            syncId: 'i7',
            status: 'paid',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ),
        ],
      );
      expect(result.inserted, 1);
      final row = (await db.query('invoices', where: "sync_id = 'i7'")).first;
      expect(row['status'], 'paid');
    });
  });

  // ── Batch merge ───────────────────────────────────────────────────────────

  group('Batch merge', () {
    test('processes multiple rows in one call', () async {
      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          _party(
            syncId: 'b1',
            name: 'A',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ),
          _party(
            syncId: 'b2',
            name: 'B',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ),
          _party(
            syncId: 'b3',
            name: 'C',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ),
        ],
      );
      expect(result.inserted, 3);
      expect(result.total, 3);
    });

    test('handles mixed insert/update/skip in one batch', () async {
      // pre-seed two rows
      await db.insert(
        'parties',
        _party(
          syncId: 'c1',
          name: 'old',
          updatedAt: '2026-03-17T08:00:00.000Z',
        ),
      );
      await db.insert(
        'parties',
        _party(
          syncId: 'c2',
          name: 'newer',
          updatedAt: '2026-03-17T12:00:00.000Z',
        ),
      );

      final result = await merge.mergeTable(
        db: db,
        table: 'parties',
        deviceId: deviceId,
        remoteRows: [
          _party(
            syncId: 'c1',
            name: 'updated',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ), // update c1
          _party(
            syncId: 'c2',
            name: 'stale',
            updatedAt: '2026-03-17T09:00:00.000Z',
          ), // skip c2
          _party(
            syncId: 'c3',
            name: 'brand new',
            updatedAt: '2026-03-17T10:00:00.000Z',
          ), // insert c3
        ],
      );
      expect(result.inserted, 1);
      expect(result.updated, 1);
      expect(result.skipped, 1);
    });
  });
}
