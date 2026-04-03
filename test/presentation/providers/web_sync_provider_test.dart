import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/presentation/providers/web_sync_provider.dart';

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
}
