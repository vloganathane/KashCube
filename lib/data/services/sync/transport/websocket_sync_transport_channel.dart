import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'sync_transport_channel.dart';

class WebSocketSyncTransportChannel implements SyncTransportChannel {
  WebSocketChannel? _channel;

  @override
  Future<void> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
  }

  @override
  Stream<dynamic> get stream {
    final channel = _channel;
    if (channel == null) {
      return const Stream<dynamic>.empty();
    }
    return channel.stream;
  }

  @override
  void sendJson(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(payload));
  }

  @override
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }
}
