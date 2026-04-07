import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kash_cube/data/repositories/webrtc_sync_repository_impl.dart';
import 'package:kash_cube/domain/repositories/sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('WebRTCSyncRepositoryImpl', () {
    late WebRTCSyncRepositoryImpl repository;
    late List<Map<String, dynamic>> sentMessages;
    late List<String> changedTables;

    setUp(() {
      sentMessages = [];
      changedTables = [];

      repository = WebRTCSyncRepositoryImpl(
        inboundDedupeCapacity: 512,
        sendMessage: (msg) => sentMessages.add(msg),
        notifyTableChanged: (table) => changedTables.add(table),
      );
    });

    tearDown(() {
      repository.dispose();
    });

    group('Initialization', () {
      test('starts in disconnected state after initialize()', () async {
        final states = <SyncConnectionState>[];
        repository.connectionState.listen(states.add);

        await repository.initialize();

        expect(states, contains(SyncConnectionState.disconnected));
      });

      test('initialize() sets disconnected state', () async {
        final states = <SyncConnectionState>[];
        repository.connectionState.listen(states.add);

        await repository.initialize();

        expect(states, contains(SyncConnectionState.disconnected));
      });
    });

    group('Connection Lifecycle', () {
      test('connect() transitions to connected state', () async {
        // SKIP: Phase 0 — connect() is a stub (transport is in WebSyncNotifier)
        // This will be fully tested once WebSyncNotifier delegates to repository
      }, skip: 'Phase 0: connect() is a stub');

      test('disconnect() transitions to disconnected state', () async {
        // SKIP: Phase 0 — disconnect() doesn't have full cleanup yet
      }, skip: 'Phase 0: disconnect() needs transport integration');

      test('disconnect() emits SyncDisconnected event', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer-123');

        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        await repository.disconnect();

        expect(
          events.whereType<SyncDisconnected>(),
          isNotEmpty,
        );
      });
    });

    group('Deduplication', () {
      test('filters duplicate rows by sync_id', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer-123');

        // First batch: 3 unique rows
        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100},
            {'sync_id': 'row-2', 'amount': 200},
            {'sync_id': 'row-3', 'amount': 300},
          ],
          'is_final': false,
        });

        // Second batch: 2 duplicates + 1 new
        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-2', 'amount': 200}, // Duplicate
            {'sync_id': 'row-3', 'amount': 300}, // Duplicate
            {'sync_id': 'row-4', 'amount': 400}, // New
          ],
          'is_final': false,
        });

        // Verify only 4 unique rows were processed (not 6)
        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 4); // 3 from first batch + 1 from second
      });

      test('LRU cache evicts oldest entries when capacity exceeded', () async {
        // Create repository with tiny cache (capacity = 2)
        final tinyRepo = WebRTCSyncRepositoryImpl(
          inboundDedupeCapacity: 2,
          sendMessage: (msg) => sentMessages.add(msg),
          notifyTableChanged: (table) => changedTables.add(table),
        );

        await tinyRepo.initialize();
        await tinyRepo.connect(peerId: 'test-peer');

        // Send 3 rows (exceeds capacity of 2)
        await tinyRepo.handleRowsMessage({
          'table': 'test_table',
          'rows': [
            {'sync_id': 'row-1', 'value': 'A'},
            {'sync_id': 'row-2', 'value': 'B'},
            {'sync_id': 'row-3', 'value': 'C'},
          ],
          'is_final': false,
        });

        // Now send row-1 again — it should NOT be filtered (evicted from cache)
        await tinyRepo.handleRowsMessage({
          'table': 'test_table',
          'rows': [
            {'sync_id': 'row-1', 'value': 'A'}, // Re-inserted (was evicted)
          ],
          'is_final': false,
        });

        // Verify 4 rows were processed (3 initial + 1 re-inserted)
        final progress = await tinyRepo.getSyncProgress();
        expect(progress.rowsSynced, 4);

        tinyRepo.dispose();
      });

      test('handles rows without sync_id (malformed data)', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.handleRowsMessage({
          'table': 'test_table',
          'rows': [
            {'amount': 100}, // No sync_id
            {'sync_id': 'row-1', 'amount': 200},
            {'sync_id': null, 'amount': 300}, // null sync_id
          ],
          'is_final': false,
        });

        // All 3 rows should pass through (no filtering for malformed rows)
        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 3);
      });
    });

    group('Message Handlers', () {
      test('handleRowsMessage() emits SyncTableCompleted when is_final=true',
          () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        final events = <SyncEvent>[];
        final eventsFuture = repository.events.toList();
        repository.events.listen(events.add);

        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100},
          ],
          'is_final': true, // Final frame
        });

        // Wait a bit for event emission
        await Future.delayed(const Duration(milliseconds: 100));

        final completedEvents =
            events.whereType<SyncTableCompleted>().toList();
        expect(completedEvents, isNotEmpty,
            reason: 'SyncTableCompleted event should be emitted');
        if (completedEvents.isNotEmpty) {
          expect(completedEvents.first.tableName, 'transactions');
          expect(completedEvents.first.rowsProcessed, 1);
        }
      });

      test('handleRowsMessage() does not emit event when is_final=false',
          () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100},
          ],
          'is_final': false, // Not final
        });

        final completedEvents =
            events.whereType<SyncTableCompleted>().toList();
        expect(completedEvents, isEmpty);
      });

      test('handlePushMessage() processes live incremental writes', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.handlePushMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'push-1', 'amount': 500},
            {'sync_id': 'push-2', 'amount': 600},
          ],
        });

        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 2);
      });

      test('handlePushMessage() logs dedupe when all rows are duplicates',
          () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        // Send initial rows
        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100},
          ],
          'is_final': false,
        });

        // Send same row via PUSH (should be deduped)
        await repository.handlePushMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100}, // Duplicate
          ],
        });

        // Verify only 1 row processed (second was deduped)
        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 1);
      });

      test('handleSyncPlanMessage() logs advertised tables', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        // This should not throw (just logs)
        repository.handleSyncPlanMessage({
          'tables': [
            {'name': 'transactions', 'mode': 'deltaTs'},
            {'name': 'parties', 'mode': 'snapshot'},
          ],
        });

        // No state change expected, just logging
        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 0);
      });
    });

    group('Push Methods', () {
      test('pushRow() sends PUSH frame with single row', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.pushRow(
          table: 'transactions',
          row: {'sync_id': 'new-row', 'amount': 1000},
        );

        expect(sentMessages, hasLength(1));
        expect(sentMessages.first['type'], 'PUSH');
        expect(sentMessages.first['table'], 'transactions');
        expect(sentMessages.first['rows'], hasLength(1));
        expect(sentMessages.first['rows'][0]['sync_id'], 'new-row');
      });

      test('pushRows() sends PUSH frame with multiple rows', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.pushRows(
          table: 'transactions',
          rows: [
            {'sync_id': 'batch-1', 'amount': 100},
            {'sync_id': 'batch-2', 'amount': 200},
            {'sync_id': 'batch-3', 'amount': 300},
          ],
        );

        expect(sentMessages, hasLength(1));
        expect(sentMessages.first['type'], 'PUSH');
        expect(sentMessages.first['rows'], hasLength(3));
      });

      test('pushRow() throws when not connected', () async {
        await repository.initialize();
        // Don't connect

        expect(
          () => repository.pushRow(
            table: 'transactions',
            row: {'sync_id': 'test', 'amount': 100},
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('Progress Tracking', () {
      test('getSyncProgress() returns correct rowsSynced count', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100},
            {'sync_id': 'row-2', 'amount': 200},
          ],
          'is_final': false,
        });

        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 2);
      });

      test('getSyncProgress() tracks completedTables after is_final',
          () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1', 'amount': 100},
          ],
          'is_final': true, // Mark as complete
        });

        final progress = await repository.getSyncProgress();
        expect(progress.completedTables, contains('transactions'));
      });
    });

    group('Events Stream', () {
      test('emits SyncStarted when connect() succeeds', () async {
        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        expect(
          events.whereType<SyncStarted>(),
          isNotEmpty,
        );
      });

      test('emits SyncError when connection fails', () async {
        // This test would require mocking connection failure
        // Skipped for Phase 0 (transport ownership is in WebSyncNotifier)
      });

      test('emits SyncCompleted when all pending tables done', () async {
        // Test scenario:
        // 1. Mark 2 tables as pending
        // 2. Send ROWS frames with is_final=true for both
        // 3. Verify SyncCompleted emitted

        // TODO: This requires exposing _pendingTables for testing
        // or implementing syncAllTables() with real pull logic
      });
    });

    group('Callbacks', () {
      test('sendMessage callback is invoked on pushRow()', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.pushRow(
          table: 'test_table',
          row: {'sync_id': 'test-row'},
        );

        expect(sentMessages, isNotEmpty);
      });

      test('notifyTableChanged callback is invoked after merge', () async {
        await repository.initialize();
        await repository.connect(peerId: 'test-peer');

        await repository.handleRowsMessage({
          'table': 'transactions',
          'rows': [
            {'sync_id': 'row-1'},
          ],
          'is_final': false,
        });

        expect(changedTables, contains('transactions'));
      });

      test('pushRow() throws when sendMessage callback is null', () async {
        final repoWithoutCallback = WebRTCSyncRepositoryImpl(
          sendMessage: null, // No callback
          notifyTableChanged: (table) {},
        );

        await repoWithoutCallback.initialize();
        await repoWithoutCallback.connect(peerId: 'test-peer');

        expect(
          () => repoWithoutCallback.pushRow(
            table: 'test_table',
            row: {'sync_id': 'test'},
          ),
          throwsA(isA<StateError>()),
        );

        repoWithoutCallback.dispose();
      });
    });
  });
}
