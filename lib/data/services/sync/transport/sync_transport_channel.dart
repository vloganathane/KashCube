import 'dart:async';

/// Transport abstraction for browser sync channels.
///
/// Current implementation uses WebSocket. A future WebRTC DataChannel adapter
/// can implement the same contract and be swapped by policy.
abstract class SyncTransportChannel {
  Future<void> connect(Uri uri);

  Stream<dynamic> get stream;

  void sendJson(Map<String, dynamic> payload);

  Future<void> close();
}
