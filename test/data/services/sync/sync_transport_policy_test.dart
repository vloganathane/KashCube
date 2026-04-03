import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/sync/transport/cloud_signaling_transport_channel.dart';
import 'package:kash_cube/data/services/sync/transport/sync_transport_policy.dart';
import 'package:kash_cube/data/services/sync/transport/websocket_sync_transport_channel.dart';

void main() {
  group('SyncTransportPolicy signaling mode', () {
    test('picks cloud relay when preferred', () {
      final mode = SyncTransportPolicy.pickSignalingMode(
        preferCloudSignaling: true,
      );
      expect(mode, SyncSignalingMode.cloudRelay);
    });

    test('creates unavailable placeholder for cloud signaling mode', () async {
      final channel = SyncTransportPolicy.createSignaling(
        SyncSignalingMode.cloudRelay,
        transportKind: SyncTransportKind.webSocket,
      );

      expect(channel, isA<CloudSignalingUnavailableTransportChannel>());
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
  });
}
