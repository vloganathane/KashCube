import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/sync_transport_channel.dart';
import 'package:kash_cube/presentation/providers/web_sync_provider.dart';

class _FakeSyncTransportChannel implements SyncTransportChannel {
  final List<Map<String, dynamic>> sentPayloads = <Map<String, dynamic>>[];

  @override
  Future<void> connect(Uri uri) async {}

  @override
  Stream<dynamic> get stream => const Stream<dynamic>.empty();

  @override
  void sendJson(Map<String, dynamic> payload) {
    sentPayloads.add(Map<String, dynamic>.from(payload));
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('WebSyncNotifier heartbeat reconnect', () {
    test('schedules reconnect on HEARTBEAT_TIMEOUT when session is available', () async {
      var reconnectAttempts = 0;
      final notifier = WebSyncNotifier(
        sessionIdProvider: () => 'sess-reconnect',
        heartbeatReconnectBaseDelay: const Duration(milliseconds: 5),
        maxHeartbeatReconnectAttempts: 3,
        reconnectRunner: (wsUrl, sessionId) async {
          reconnectAttempts += 1;
          return true;
        },
      );
      notifier.setWsUrlForTest('ws://127.0.0.1:9001/ws');

      notifier.ingestMessageForTest(<String, dynamic>{
        'type': 'SIGNAL_ERROR',
        'code': 'HEARTBEAT_TIMEOUT',
        'reason': 'Control plane heartbeat timeout',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(reconnectAttempts, 1);
      expect(notifier.state.progressMsg, 'Reconnected after heartbeat timeout');

      notifier.dispose();
    });

    test('does not reconnect when session id is unavailable', () async {
      var reconnectAttempts = 0;
      final notifier = WebSyncNotifier(
        sessionIdProvider: () => null,
        heartbeatReconnectBaseDelay: const Duration(milliseconds: 5),
        reconnectRunner: (wsUrl, sessionId) async {
          reconnectAttempts += 1;
          return true;
        },
      );
      notifier.setWsUrlForTest('ws://127.0.0.1:9002/ws');

      notifier.ingestMessageForTest(<String, dynamic>{
        'type': 'SIGNAL_ERROR',
        'code': 'HEARTBEAT_TIMEOUT',
        'reason': 'Control plane heartbeat timeout',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(reconnectAttempts, 0);
      expect(notifier.state.progressMsg, 'Connection lost. Auto-reconnect unavailable.');

      notifier.dispose();
    });

    test('stops retries after max reconnect attempts', () async {
      var reconnectAttempts = 0;
      final notifier = WebSyncNotifier(
        sessionIdProvider: () => 'sess-retry',
        heartbeatReconnectBaseDelay: const Duration(milliseconds: 5),
        maxHeartbeatReconnectAttempts: 2,
        reconnectRunner: (wsUrl, sessionId) async {
          reconnectAttempts += 1;
          return false;
        },
      );
      notifier.setWsUrlForTest('ws://127.0.0.1:9003/ws');

      notifier.ingestMessageForTest(<String, dynamic>{
        'type': 'SIGNAL_ERROR',
        'code': 'HEARTBEAT_TIMEOUT',
        'reason': 'Control plane heartbeat timeout',
      });

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(reconnectAttempts, 2);
      expect(notifier.state.progressMsg, 'Connection lost. Please reconnect.');

      notifier.dispose();
    });
  });

  group('WebSyncNotifier outbound WRITE ack/retry', () {
    test('clears pending write when WRITE_OK arrives', () {
      final channel = _FakeSyncTransportChannel();
      final notifier = WebSyncNotifier();
      notifier.setChannelForTest(channel);

      notifier.enqueueOutboundWriteForTest(<String, dynamic>{
        'type': 'WRITE',
        'table': 'transactions',
        'sync_id': 'sync-ack-1',
        'row': <String, dynamic>{'sync_id': 'sync-ack-1'},
      });

      expect(notifier.pendingOutboundWriteCountForTest, 1);
      expect(channel.sentPayloads, hasLength(1));

      notifier.ingestMessageForTest(<String, dynamic>{
        'type': 'WRITE_OK',
        'sync_id': 'sync-ack-1',
      });

      expect(notifier.pendingOutboundWriteCountForTest, 0);

      notifier.dispose();
    });

    test('retries stale pending writes with retry markers', () async {
      final channel = _FakeSyncTransportChannel();
      final notifier = WebSyncNotifier(
        writeAckTimeout: const Duration(milliseconds: 5),
        maxWriteRetryAttempts: 3,
      );
      notifier.setChannelForTest(channel);

      notifier.enqueueOutboundWriteForTest(<String, dynamic>{
        'type': 'WRITE',
        'table': 'transactions',
        'sync_id': 'sync-retry-1',
        'row': <String, dynamic>{'sync_id': 'sync-retry-1'},
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      notifier.retryPendingWritesForTest();

      expect(channel.sentPayloads, hasLength(2));
      expect(channel.sentPayloads.first['retry_count'], 0);
      expect(channel.sentPayloads.last['retry_count'], 1);
      expect(channel.sentPayloads.last['is_retry'], isTrue);
      expect(notifier.pendingOutboundWriteCountForTest, 1);

      notifier.dispose();
    });

    test('stops retrying pending writes after max attempts', () async {
      final channel = _FakeSyncTransportChannel();
      final notifier = WebSyncNotifier(
        writeAckTimeout: const Duration(milliseconds: 5),
        maxWriteRetryAttempts: 2,
      );
      notifier.setChannelForTest(channel);

      notifier.enqueueOutboundWriteForTest(<String, dynamic>{
        'type': 'WRITE',
        'table': 'transactions',
        'sync_id': 'sync-max-1',
        'row': <String, dynamic>{'sync_id': 'sync-max-1'},
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      notifier.retryPendingWritesForTest();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      notifier.retryPendingWritesForTest();

      expect(channel.sentPayloads, hasLength(2));
      expect(
        notifier.state.progressMsg,
        'Write delivery pending confirmation. Reconnect may be required.',
      );
      expect(notifier.pendingOutboundWriteCountForTest, 1);

      notifier.dispose();
    });
  });
}
