import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kash_cube/data/repositories/libp2p_sync_repository_impl.dart';
import 'package:kash_cube/domain/repositories/sync_repository.dart';
import 'package:kash_cube/data/services/libp2p/libp2p_node.dart';
import 'package:kash_cube/data/services/libp2p/libp2p_protocol.dart';
import 'package:kash_cube/data/services/libp2p/libp2p_discovery.dart';

class MockLibP2pNode extends LibP2pNode {
  bool initializeCalled = false;
  bool startCalled = false;
  bool closeCalled = false;
  final List<Map<String, dynamic>> registeredProtocols = [];

  @override
  Future<void> initialize({
    Uint8List? identity,
    List<String>? listenAddrs,
  }) async {
    initializeCalled = true;
  }

  @override
  Future<void> start() async {
    startCalled = true;
  }

  @override
  Future<void> close() async {
    closeCalled = true;
  }

  @override
  void registerProtocol(String protocolId, dynamic handler) {
    registeredProtocols.add({'protocolId': protocolId, 'handler': handler});
  }
}

class MockLibP2pProtocol extends LibP2pProtocol {
  final Map<String, FrameHandler> _handlers = {};

  @override
  void registerHandler(String frameType, FrameHandler handler) {
    _handlers[frameType] = handler;
  }

  /// Helper for tests to trigger frame handlers
  Future<Map<String, dynamic>?> triggerHandler(
    String frameType,
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final handler = _handlers[frameType];
    if (handler == null) {
      throw StateError('No handler registered for $frameType');
    }
    return handler(frame, peerId);
  }
}

class MockLibP2pDiscovery extends LibP2pDiscovery {
  final StreamController<SyncPeer> _controller =
      StreamController<SyncPeer>.broadcast();
  bool startCalled = false;
  bool stopCalled = false;

  @override
  Stream<SyncPeer> get discoveredPeers => _controller.stream;

  @override
  Future<void> start({
    required dynamic host, // Using dynamic to avoid importing dart_libp2p in tests
    Map<String, String>? metadata,
  }) async {
    startCalled = true;
    // Emit a test peer immediately
    _controller.add(SyncPeer(
      peerId: 'test-peer-123',
      displayName: 'Test Device',
      discoveredAt: DateTime.now(),
    ));
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    await _controller.close();
  }

  void emitPeer(SyncPeer peer) {
    _controller.add(peer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Libp2pSyncRepositoryImpl', () {
    late Libp2pSyncRepositoryImpl repository;
    late MockLibP2pNode mockNode;
    late MockLibP2pProtocol mockProtocol;
    late MockLibP2pDiscovery mockDiscovery;

    setUp(() {
      mockNode = MockLibP2pNode();
      mockProtocol = MockLibP2pProtocol();
      mockDiscovery = MockLibP2pDiscovery();

      repository = Libp2pSyncRepositoryImpl(
        node: mockNode,
        protocol: mockProtocol,
        discovery: mockDiscovery,
        inboundDedupeCapacity: 512,
      );
    });

    tearDown(() {
      repository.dispose();
    });

    group('Initialization', () {
      test('initialize() calls LibP2pNode lifecycle methods', () async {
        await repository.initialize();

        expect(mockNode.initializeCalled, isTrue);
        expect(mockNode.startCalled, isTrue);
      });

      test('starts in disconnected state after initialize()', () async {
        final states = <SyncConnectionState>[];
        repository.connectionState.listen(states.add);

        await repository.initialize();

        expect(states, contains(SyncConnectionState.disconnected));
      });

      test('registers frame handlers for all protocol types', () async {
        await repository.initialize();

        // Protocol handlers should be registered via _registerProtocolHandlers()
        // Verify by checking if ROWS handler exists
        expect(mockProtocol._handlers.containsKey('ROWS'), isTrue);
        expect(mockProtocol._handlers.containsKey('PUSH'), isTrue);
        expect(mockProtocol._handlers.containsKey('PING'), isTrue);
      });
    });

    group('Connection Lifecycle', () {
      test('disconnect() emits SyncDisconnected event', () async {
        await repository.initialize();

        final events = <SyncEvent>[];
        final subscription = repository.events.listen(events.add);

        await repository.disconnect();

        // Wait for async event processing
        await Future.delayed(const Duration(milliseconds: 100));

        expect(
          events.whereType<SyncDisconnected>(),
          isNotEmpty,
        );

        await subscription.cancel();
      });

      test('disconnect() calls LibP2pNode.close()', () async {
        await repository.initialize();
        
        // Need to start discovery first to have something to stop
        await repository.stopDiscovery();
        
        await repository.disconnect();

        expect(mockNode.closeCalled, isTrue);
      });

      test('disconnect() clears internal state', () async {
        await repository.initialize();

        // Simulate some sync progress
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'test_table',
            'rows': [
              {'sync_id': 'row-1', 'value': 'A'}
            ],
            'is_final': true,
          },
          'test-peer',
        );

        final progressBefore = await repository.getSyncProgress();
        expect(progressBefore.rowsSynced, 1);

        await repository.disconnect();

        final progressAfter = await repository.getSyncProgress();
        expect(progressAfter.rowsSynced, 0);
        expect(progressAfter.completedTables, isEmpty);
      });
    });

    group('Discovery', () {
      test('discoverPeers() starts mDNS discovery', () async {
        await repository.initialize();

        final peersStream = repository.discoverPeers();

        // Wait for discovery to start
        await Future.delayed(const Duration(milliseconds: 100));

        expect(mockDiscovery.startCalled, isTrue);

        await repository.stopDiscovery();
      });

      test('discoverPeers() emits discovered peers', () async {
        await repository.initialize();

        final peersStream = repository.discoverPeers();
        final peerLists = <List<SyncPeer>>[];

        final subscription = peersStream.listen(peerLists.add);

        // Manually emit a peer to trigger the stream
        mockDiscovery.emitPeer(SyncPeer(
          peerId: 'test-peer-456',
          displayName: 'Another Device',
          discoveredAt: DateTime.now(),
        ));

        // Wait for emission
        await Future.delayed(const Duration(milliseconds: 200));

        expect(peerLists.length, greaterThan(0));
        expect(peerLists.last, isNotEmpty);

        await subscription.cancel();
        await repository.stopDiscovery();
      });

      test('stopDiscovery() stops mDNS', () async {
        await repository.initialize();
        repository.discoverPeers();

        await Future.delayed(const Duration(milliseconds: 100));
        await repository.stopDiscovery();

        expect(mockDiscovery.stopCalled, isTrue);
      });
    });

    group('Deduplication', () {
      test('filters duplicate rows by sync_id', () async {
        await repository.initialize();

        // First batch: 3 unique rows
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-1', 'amount': 100},
              {'sync_id': 'row-2', 'amount': 200},
              {'sync_id': 'row-3', 'amount': 300},
            ],
            'is_final': false,
          },
          'test-peer',
        );

        // Second batch: 2 duplicates + 1 new
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-2', 'amount': 200}, // Duplicate
              {'sync_id': 'row-3', 'amount': 300}, // Duplicate
              {'sync_id': 'row-4', 'amount': 400}, // New
            ],
            'is_final': false,
          },
          'test-peer',
        );

        // Verify only 4 unique rows were processed (not 6)
        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 4); // 3 from first batch + 1 from second
      });

      test('LRU cache evicts oldest entries when capacity exceeded', () async {
        // Create repository with tiny cache (capacity = 2)
        final tinyRepo = Libp2pSyncRepositoryImpl(
          node: mockNode,
          protocol: mockProtocol,
          discovery: mockDiscovery,
          inboundDedupeCapacity: 2,
        );

        await tinyRepo.initialize();

        // Send 3 rows (exceeds capacity of 2)
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'test_table',
            'rows': [
              {'sync_id': 'row-1', 'value': 'A'},
              {'sync_id': 'row-2', 'value': 'B'},
              {'sync_id': 'row-3', 'value': 'C'},
            ],
            'is_final': false,
          },
          'test-peer',
        );

        // Now send row-1 again — it should NOT be filtered (evicted from cache)
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'test_table',
            'rows': [
              {'sync_id': 'row-1', 'value': 'A'}, // Re-inserted (was evicted)
            ],
            'is_final': false,
          },
          'test-peer',
        );

        // Verify 4 rows were processed (3 initial + 1 re-inserted)
        final progress = await tinyRepo.getSyncProgress();
        expect(progress.rowsSynced, 4);

        tinyRepo.dispose();
      });

      test('handles rows without sync_id (malformed data)', () async {
        await repository.initialize();

        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'test_table',
            'rows': [
              {'value': 'A'}, // No sync_id
              {'sync_id': 'row-2', 'value': 'B'},
            ],
            'is_final': false,
          },
          'test-peer',
        );

        // Both rows should pass through (malformed rows not filtered)
        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 2);
      });
    });

    group('Frame Handlers', () {
      test('handleRowsFrame() emits SyncTableCompleted when is_final=true',
          () async {
        await repository.initialize();

        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-1', 'amount': 100}
            ],
            'is_final': true,
          },
          'test-peer',
        );

        final completedEvents = events.whereType<SyncTableCompleted>();
        expect(completedEvents, isNotEmpty);
        expect(completedEvents.first.tableName, 'transactions');
      });

      test('handleRowsFrame() does not emit event when is_final=false',
          () async {
        await repository.initialize();

        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-1', 'amount': 100}
            ],
            'is_final': false,
          },
          'test-peer',
        );

        final completedEvents = events.whereType<SyncTableCompleted>();
        expect(completedEvents, isEmpty);
      });

      test('handlePushFrame() processes live incremental writes', () async {
        await repository.initialize();

        await mockProtocol.triggerHandler(
          'PUSH',
          {
            'type': 'PUSH',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'push-1', 'amount': 500}
            ],
          },
          'test-peer',
        );

        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 1);
      });

      test('handlePushFrame() returns WRITE_OK acknowledgment', () async {
        await repository.initialize();

        final response = await mockProtocol.triggerHandler(
          'PUSH',
          {
            'type': 'PUSH',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'push-1', 'amount': 500}
            ],
          },
          'test-peer',
        );

        expect(response, isNotNull);
        expect(response!['type'], 'WRITE_OK');
        expect(response['table'], 'transactions');
        expect(response['count'], 1);
      });

      test('handlePushFrame() deduplicates duplicate rows', () async {
        await repository.initialize();

        // First push
        await mockProtocol.triggerHandler(
          'PUSH',
          {
            'type': 'PUSH',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'push-1', 'amount': 500}
            ],
          },
          'test-peer',
        );

        // Duplicate push
        final response = await mockProtocol.triggerHandler(
          'PUSH',
          {
            'type': 'PUSH',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'push-1', 'amount': 500} // Same sync_id
            ],
          },
          'test-peer',
        );

        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 1); // Only first counted
        expect(response!['count'], 0); // WRITE_OK with 0 count
      });

      test('handleErrorFrame() emits SyncError event', () async {
        await repository.initialize();

        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        await mockProtocol.triggerHandler(
          'ERROR',
          {
            'type': 'ERROR',
            'code': 'DB_CONSTRAINT',
            'message': 'Foreign key violation',
          },
          'test-peer',
        );

        final errorEvents = events.whereType<SyncError>();
        expect(errorEvents, isNotEmpty);
        expect(errorEvents.first.message, contains('Remote error'));
      });

      test('handlePingFrame() responds with PONG', () async {
        await repository.initialize();

        final response = await mockProtocol.triggerHandler(
          'PING',
          {'type': 'PING'},
          'test-peer',
        );

        expect(response, isNotNull);
        expect(response!['type'], 'PONG');
      });

      test('handlePongFrame() logs keepalive response', () async {
        await repository.initialize();

        // Should not throw
        await mockProtocol.triggerHandler(
          'PONG',
          {'type': 'PONG'},
          'test-peer',
        );
      });

      test('handleSyncPlanFrame() logs advertised tables', () async {
        await repository.initialize();

        // Should not throw
        await mockProtocol.triggerHandler(
          'SYNC_PLAN',
          {
            'type': 'SYNC_PLAN',
            'tables': [
              {'name': 'transactions', 'mode': 'delta_ts'},
              {'name': 'credits', 'mode': 'snapshot'},
            ],
          },
          'test-peer',
        );
      });
    });

    group('Sync Progress', () {
      test('getSyncProgress() returns correct rowsSynced count', () async {
        await repository.initialize();

        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-1', 'amount': 100},
              {'sync_id': 'row-2', 'amount': 200},
            ],
            'is_final': false,
          },
          'test-peer',
        );

        final progress = await repository.getSyncProgress();
        expect(progress.rowsSynced, 2);
      });

      test('getSyncProgress() tracks completedTables after is_final',
          () async {
        await repository.initialize();

        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-1', 'amount': 100}
            ],
            'is_final': true,
          },
          'test-peer',
        );

        final progress = await repository.getSyncProgress();
        expect(progress.completedTables, contains('transactions'));
        expect(progress.isComplete, isTrue);
      });

      test('percentComplete calculation', () async {
        await repository.initialize();

        // Add one pending table
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'table1',
            'rows': [],
            'is_final': false,
          },
          'test-peer',
        );

        // Complete it
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'table1',
            'rows': [],
            'is_final': true,
          },
          'test-peer',
        );

        final progress = await repository.getSyncProgress();
        expect(progress.percentComplete, 100.0);
      });
    });

    group('Events', () {
      test('emits SyncCompleted when all pending tables done', () async {
        await repository.initialize();

        final events = <SyncEvent>[];
        repository.events.listen(events.add);

        // Complete one table
        await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            'table': 'transactions',
            'rows': [
              {'sync_id': 'row-1', 'amount': 100}
            ],
            'is_final': true,
          },
          'test-peer',
        );

        final completedEvents = events.whereType<SyncCompleted>();
        expect(completedEvents, isNotEmpty);
        expect(completedEvents.first.totalRowsSynced, 1);
      });
    });

    group('Error Handling', () {
      test('handleRowsFrame() returns ERROR on malformed frame', () async {
        await repository.initialize();

        final response = await mockProtocol.triggerHandler(
          'ROWS',
          {
            'type': 'ROWS',
            // Missing 'table' field
            'rows': [],
          },
          'test-peer',
        );

        expect(response, isNotNull);
        expect(response!['type'], 'ERROR');
        expect(response['code'], 'MALFORMED_FRAME');
      });

      test('handlePushFrame() returns ERROR on malformed frame', () async {
        await repository.initialize();

        final response = await mockProtocol.triggerHandler(
          'PUSH',
          {
            'type': 'PUSH',
            // Missing 'table' and 'rows'
          },
          'test-peer',
        );

        expect(response, isNotNull);
        expect(response!['type'], 'ERROR');
        expect(response['code'], 'MALFORMED_FRAME');
      });
    });
  });
}
