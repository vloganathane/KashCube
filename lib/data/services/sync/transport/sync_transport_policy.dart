import 'sync_transport_channel.dart';
import 'webrtc_sync_transport_channel.dart';
import 'websocket_sync_transport_channel.dart';

enum SyncTransportKind {
  webSocket,
  webRtc,
}

class SyncTransportPolicy {
  static SyncTransportKind pick({required bool preferWebRtc}) {
    return preferWebRtc ? SyncTransportKind.webRtc : SyncTransportKind.webSocket;
  }

  static SyncTransportChannel create(SyncTransportKind kind) {
    switch (kind) {
      case SyncTransportKind.webSocket:
        return WebSocketSyncTransportChannel();
      case SyncTransportKind.webRtc:
        return WebRtcSyncTransportChannel();
    }
  }
}
