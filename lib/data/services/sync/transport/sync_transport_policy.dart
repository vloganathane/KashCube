import 'cloud_signaling_transport_channel.dart';
import 'sync_transport_channel.dart';
import 'webrtc_peer_ops.dart';
import 'webrtc_sync_transport_channel.dart';
import 'websocket_sync_transport_channel.dart';

enum SyncTransportKind {
  webSocket,
  webRtc,
}

enum SyncSignalingMode {
  localLan,
  cloudRelay,
}

class SyncTransportPolicy {
  static SyncTransportKind pick({required bool preferWebRtc}) {
    return preferWebRtc ? SyncTransportKind.webRtc : SyncTransportKind.webSocket;
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

  static SyncSignalingMode pickSignalingMode({required bool preferCloudSignaling}) {
    return preferCloudSignaling
        ? SyncSignalingMode.cloudRelay
        : SyncSignalingMode.localLan;
  }

  static SyncTransportChannel createSignaling(
    SyncSignalingMode mode, {
    required SyncTransportKind transportKind,
    WebRtcPeerOpsFactory? peerOpsFactory,
    CloudSignalingAdapterFactory? cloudAdapterFactory,
  }) {
    switch (mode) {
      case SyncSignalingMode.localLan:
        return create(transportKind, peerOpsFactory: peerOpsFactory);
      case SyncSignalingMode.cloudRelay:
        return CloudSignalingTransportChannel(
          adapterFactory: cloudAdapterFactory,
        );
    }
  }
}
