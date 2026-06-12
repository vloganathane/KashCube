import 'cloud_signaling_transport_channel.dart';
import 'sync_transport_channel.dart';
import 'webrtc_peer_ops.dart';
import 'webrtc_sync_transport_channel.dart';
import 'websocket_sync_transport_channel.dart';

enum SyncTransportKind { webSocket, webRtc }

enum SyncSignalingMode { localLan, cloudRelay }

enum SyncTurnRelayMode { disabled, preferred, required }

class SyncTransportPolicy {
  static SyncTransportKind pick({required bool preferWebRtc}) {
    return preferWebRtc
        ? SyncTransportKind.webRtc
        : SyncTransportKind.webSocket;
  }

  static SyncTransportChannel create(
    SyncTransportKind kind, {
    WebRtcPeerOpsFactory? peerOpsFactory,
  }) {
    switch (kind) {
      case SyncTransportKind.webSocket:
        return WebSocketSyncTransportChannel();
      case SyncTransportKind.webRtc:
        return WebRtcSyncTransportChannel(peerOpsFactory: peerOpsFactory);
    }
  }

  static SyncSignalingMode pickSignalingMode({
    required bool preferCloudSignaling,
  }) {
    return preferCloudSignaling
        ? SyncSignalingMode.cloudRelay
        : SyncSignalingMode.localLan;
  }

  static SyncTransportChannel createSignaling(
    SyncSignalingMode mode, {
    required SyncTransportKind transportKind,
    WebRtcPeerOpsFactory? peerOpsFactory,
    CloudSignalingAdapterFactory? cloudAdapterFactory,
    SyncTurnRelayMode turnRelayMode = SyncTurnRelayMode.disabled,
    List<String> relayServerHints = const <String>[],
  }) {
    switch (mode) {
      case SyncSignalingMode.localLan:
        return create(transportKind, peerOpsFactory: peerOpsFactory);
      case SyncSignalingMode.cloudRelay:
        final cloudRelayMode = switch (turnRelayMode) {
          SyncTurnRelayMode.disabled => CloudTurnRelayMode.disabled,
          SyncTurnRelayMode.preferred => CloudTurnRelayMode.preferred,
          SyncTurnRelayMode.required => CloudTurnRelayMode.required,
        };
        return CloudSignalingTransportChannel(
          adapterFactory: cloudAdapterFactory,
          sessionOptions: CloudSignalingSessionOptions(
            turnRelayMode: cloudRelayMode,
            relayServerHints: relayServerHints,
          ),
        );
    }
  }
}
