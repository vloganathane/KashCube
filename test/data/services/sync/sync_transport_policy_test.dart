import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_transport_channel.dart';
import 'package:kash_cube/data/services/sync/transport/sync_transport_policy.dart';
import 'package:kash_cube/data/services/sync/transport/websocket_sync_transport_channel.dart';

class _CapturingCloudAdapter implements CloudSignalingAdapter {
  CloudSignalingSessionOptions? lastOptions;

  @override
  Stream<Map<String, dynamic>> get inboundFrames =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> connect(
    Uri uri, {
    CloudSignalingSessionOptions options = const CloudSignalingSessionOptions(),
  }) async {
    lastOptions = options;
  }

  @override
  Future<void> sendFrame(Map<String, dynamic> payload) async {}

  @override
  Future<void> close() async {}
}

void main() {
  group('SyncTransportPolicy signaling mode', () {
    test('picks cloud relay when preferred', () {
      final mode = SyncTransportPolicy.pickSignalingMode(
        preferCloudSignaling: true,
      );
      expect(mode, SyncSignalingMode.cloudRelay);
    });

    test('creates cloud signaling adapter seam for cloud mode', () async {
      final channel = SyncTransportPolicy.createSignaling(
        SyncSignalingMode.cloudRelay,
        transportKind: SyncTransportKind.webSocket,
      );

      expect(channel, isA<CloudSignalingTransportChannel>());
      expect(
        () => channel.connect(Uri.parse('ws://127.0.0.1:8080/ws')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('creates local transport for local signaling mode', () {
      final channel = SyncTransportPolicy.createSignaling(
        SyncSignalingMode.localLan,
        transportKind: SyncTransportKind.webSocket,
      );

      expect(channel, isA<WebSocketSyncTransportChannel>());
    });

    test(
      'passes TURN relay mode into cloud signaling channel options',
      () async {
        final adapter = _CapturingCloudAdapter();
        final channel = SyncTransportPolicy.createSignaling(
          SyncSignalingMode.cloudRelay,
          transportKind: SyncTransportKind.webSocket,
          turnRelayMode: SyncTurnRelayMode.required,
          relayServerHints: const <String>['turn:relay.example.invalid:3478'],
          cloudAdapterFactory: () => adapter,
        );

        await channel.connect(Uri.parse('wss://example.invalid/signal'));

        expect(adapter.lastOptions, isNotNull);
        expect(adapter.lastOptions!.turnRelayMode, CloudTurnRelayMode.required);
        expect(adapter.lastOptions!.relayServerHints, const <String>[
          'turn:relay.example.invalid:3478',
        ]);

        await channel.close();
      },
    );
  });
}
