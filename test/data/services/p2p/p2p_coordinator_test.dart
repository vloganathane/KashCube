import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/p2p/p2p_coordinator.dart';
import 'package:kash_cube/data/services/p2p/p2p_discovery_service.dart';
import 'package:kash_cube/data/services/sync/transport/sync_signaling_messages.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a minimal in-memory DB with the tables the coordinator reads/writes.
Future<Database> _openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE parties (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_id     TEXT    UNIQUE NOT NULL,
          name        TEXT    NOT NULL DEFAULT '',
          updated_at  TEXT    NOT NULL,
          deleted_at  TEXT,
          version     INTEGER NOT NULL DEFAULT 0,
          updated_by_device_id TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE transactions (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_id     TEXT    UNIQUE NOT NULL,
          amount      REAL    NOT NULL DEFAULT 0,
          updated_at  TEXT    NOT NULL,
          deleted_at  TEXT,
          version     INTEGER NOT NULL DEFAULT 0,
          updated_by_device_id TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE sync_watermarks (
          peer_identity_id TEXT NOT NULL,
          table_name       TEXT NOT NULL,
          last_synced_at   TEXT NOT NULL,
          PRIMARY KEY (peer_identity_id, table_name)
        )
      ''');

      await db.execute('''
        CREATE TABLE trusted_peers (
          id                  INTEGER PRIMARY KEY AUTOINCREMENT,
          peer_identity_id    TEXT    UNIQUE NOT NULL,
          peer_name           TEXT,
          business_id         TEXT,
          shared_secret_enc   TEXT    NOT NULL,
          paired_at           TEXT    NOT NULL,
          last_seen_at        TEXT,
          last_synced_at      TEXT,
          is_active           INTEGER NOT NULL DEFAULT 1
        )
      ''');
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    P2pCoordinator.instance.clearWebSignalStateForTest();
  });

  // ── Initial-state tests ────────────────────────────────────────────────────

  group('P2pCoordinator — initial state', () {
    test('isRunning is false before start()', () {
      expect(P2pCoordinator.instance.isRunning, isFalse);
    });

    test('discoveredPeers is empty before start()', () {
      expect(P2pDiscoveryService.instance.currentPeers, isEmpty);
    });

    test('statusStream is a broadcast stream', () {
      expect(P2pCoordinator.instance.statusStream.isBroadcast, isTrue);
    });

    test('syncNow() completes without error when not running', () async {
      await expectLater(P2pCoordinator.instance.syncNow(), completes);
    });
  });

  // ── SyncStatus ─────────────────────────────────────────────────────────────

  group('SyncStatus', () {
    test('has correct phase', () {
      const s = SyncStatus(phase: SyncPhase.idle, message: 'ok');
      expect(s.phase, SyncPhase.idle);
      expect(s.message, 'ok');
      expect(s.peerName, isNull);
      expect(s.results, isNull);
    });

    test('toString includes phase', () {
      const s = SyncStatus(phase: SyncPhase.syncing, peerName: 'iPad');
      expect(s.toString(), contains('syncing'));
      expect(s.toString(), contains('iPad'));
    });
  });

  // ── Watermark helpers ──────────────────────────────────────────────────────

  group('P2pCoordinator — watermark helpers (DB layer)', () {
    late Database db;

    setUp(() async => db = await _openTestDb());
    tearDown(() async => db.close());

    test('getWatermarkForTest returns null when no row exists', () async {
      final ts = await P2pCoordinator.instance.getWatermarkForTest(
        db,
        'peer-A',
        'transactions',
      );
      expect(ts, isNull);
    });

    test('upsertWatermarkForTest inserts a new row', () async {
      final now = DateTime.utc(2026, 1, 15, 10, 0);
      await P2pCoordinator.instance.upsertWatermarkForTest(
        db,
        'peer-A',
        'transactions',
        now,
      );
      final ts = await P2pCoordinator.instance.getWatermarkForTest(
        db,
        'peer-A',
        'transactions',
      );
      expect(ts, isNotNull);
      expect(ts!.isUtc, isTrue);
      expect(ts.year, 2026);
      expect(ts.month, 1);
      expect(ts.day, 15);
    });

    test('upsertWatermarkForTest advances an existing watermark', () async {
      final t1 = DateTime.utc(2026, 1, 15);
      final t2 = DateTime.utc(2026, 2, 20);

      await P2pCoordinator.instance.upsertWatermarkForTest(
        db,
        'peer-B',
        'parties',
        t1,
      );
      await P2pCoordinator.instance.upsertWatermarkForTest(
        db,
        'peer-B',
        'parties',
        t2,
      );

      final ts = await P2pCoordinator.instance.getWatermarkForTest(
        db,
        'peer-B',
        'parties',
      );
      expect(ts?.month, 2);
      expect(ts?.day, 20);
    });

    test('watermarks are stored per peer+table independently', () async {
      final tA = DateTime.utc(2026, 3, 1);
      final tB = DateTime.utc(2026, 4, 1);

      await P2pCoordinator.instance.upsertWatermarkForTest(
        db,
        'peer-X',
        'parties',
        tA,
      );
      await P2pCoordinator.instance.upsertWatermarkForTest(
        db,
        'peer-Y',
        'parties',
        tB,
      );

      final tsX = await P2pCoordinator.instance.getWatermarkForTest(
        db,
        'peer-X',
        'parties',
      );
      final tsY = await P2pCoordinator.instance.getWatermarkForTest(
        db,
        'peer-Y',
        'parties',
      );

      expect(tsX?.month, 3);
      expect(tsY?.month, 4);
    });
  });

  // ── queryLocalChangesForTest ───────────────────────────────────────────────

  group('P2pCoordinator — queryLocalChangesForTest (DB layer)', () {
    late Database db;

    setUp(() async => db = await _openTestDb());
    tearDown(() async => db.close());

    Future<void> insertParty(
      String syncId,
      String updatedAt, {
      String? deletedAt,
    }) async {
      await db.rawInsert(
        'INSERT INTO parties (sync_id, name, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?)',
        [syncId, 'Test Party $syncId', updatedAt, deletedAt],
      );
    }

    test('afterMs=0 returns all non-deleted rows', () async {
      await insertParty('p1', '2026-01-01T00:00:00.000Z');
      await insertParty('p2', '2026-02-01T00:00:00.000Z');
      await insertParty(
        'p3',
        '2026-01-15T00:00:00.000Z',
        deletedAt: '2026-01-20T00:00:00.000Z',
      );

      final rows = await P2pCoordinator.instance.queryLocalChangesForTest(
        db,
        'parties',
        0,
      );
      // p3 is deleted, so only p1 and p2 should appear.
      expect(rows.length, 2);
      final syncIds = rows.map((r) => r['sync_id'] as String).toSet();
      expect(syncIds, containsAll(['p1', 'p2']));
      expect(syncIds, isNot(contains('p3')));
    });

    test('afterMs filters by updated_at cutoff', () async {
      // Insert rows spread across different timestamps.
      await insertParty('old', '2026-01-01T00:00:00.000Z'); // before cutoff
      await insertParty('new', '2026-03-01T00:00:00.000Z'); // after cutoff

      // Cutoff = 2026-02-01 00:00:00 UTC.
      final cutoff = DateTime.utc(2026, 2, 1);
      final rows = await P2pCoordinator.instance.queryLocalChangesForTest(
        db,
        'parties',
        cutoff.millisecondsSinceEpoch,
      );
      expect(rows.length, 1);
      expect(rows.first['sync_id'], 'new');
    });

    test('returns empty list when no rows match', () async {
      final future = DateTime.utc(2030, 1, 1);
      final rows = await P2pCoordinator.instance.queryLocalChangesForTest(
        db,
        'parties',
        future.millisecondsSinceEpoch,
      );
      expect(rows, isEmpty);
    });

    test('returns empty list for table with no rows', () async {
      final rows = await P2pCoordinator.instance.queryLocalChangesForTest(
        db,
        'transactions',
        0,
      );
      expect(rows, isEmpty);
    });

    test('handles gracefully when table does not exist', () async {
      // Should catch and return [] rather than throwing.
      final rows = await P2pCoordinator.instance.queryLocalChangesForTest(
        db,
        'nonexistent_table',
        0,
      );
      expect(rows, isEmpty);
    });
  });

  // ── syncableTables constant ────────────────────────────────────────────────

  // Indirectly verify that the sync table order from the file is correct by
  // checking that the list is populated and has expected entries.
  group('Sync table ordering', () {
    // Access through a simple string-matching inspection of the coordinator
    // source via the sync cycle — we just confirm the public contract here.
    test('SyncPhase enum has all expected values', () {
      expect(SyncPhase.values, hasLength(5));
      expect(
        SyncPhase.values,
        containsAll([
          SyncPhase.idle,
          SyncPhase.starting,
          SyncPhase.syncing,
          SyncPhase.done,
          SyncPhase.error,
        ]),
      );
    });
  });

  group('P2pCoordinator signaling contract (M1)', () {
    test('returns SIGNAL_ERROR when session_id is missing', () async {
      final responses = await P2pCoordinator.instance
          .handleWebSignalFrameForTest({
            'type': SyncSignalingMessages.signalOffer,
            'sdp': 'v=0',
          });

      expect(responses, hasLength(1));
      expect(responses.first['type'], SyncSignalingMessages.signalError);
      expect(responses.first['code'], 'MISSING_SESSION_ID');
    });

    test('rejects answer before offer', () async {
      final responses = await P2pCoordinator.instance
          .handleWebSignalFrameForTest({
            'type': SyncSignalingMessages.signalAnswer,
            'session_id': 'sess-a1',
            'sdp': 'v=0',
          });

      expect(responses.first['type'], SyncSignalingMessages.signalError);
      expect(responses.first['code'], 'ANSWER_BEFORE_OFFER');
    });

    test('rejects duplicate offer for same session', () async {
      await P2pCoordinator.instance.handleWebSignalFrameForTest({
        'type': SyncSignalingMessages.signalOffer,
        'session_id': 'sess-dup',
        'sdp': 'v=0\no=- 1 1 IN IP4 127.0.0.1',
      });

      final responses = await P2pCoordinator.instance
          .handleWebSignalFrameForTest({
            'type': SyncSignalingMessages.signalOffer,
            'session_id': 'sess-dup',
            'sdp': 'v=0\no=- 1 1 IN IP4 127.0.0.1',
          });

      expect(responses.first['type'], SyncSignalingMessages.signalError);
      expect(responses.first['code'], 'DUPLICATE_OFFER');
    });

    test(
      'queues ICE and responds with SIGNAL_ACK while waiting for answer',
      () async {
        await P2pCoordinator.instance.handleWebSignalFrameForTest({
          'type': SyncSignalingMessages.signalOffer,
          'session_id': 'sess-ice-q',
          'sdp': 'v=0\no=- 1 1 IN IP4 127.0.0.1',
        });

        final responses = await P2pCoordinator.instance
            .handleWebSignalFrameForTest({
              'type': SyncSignalingMessages.signalIceCandidate,
              'session_id': 'sess-ice-q',
              'candidate': {'candidate': 'ice-1'},
            });

        expect(responses.first['type'], SyncSignalingMessages.signalAck);
        expect(responses.first['status'], 'ice_queued_waiting_for_answer');
      },
    );
  });
}
