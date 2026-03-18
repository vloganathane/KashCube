import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ── WebSocket connection state ─────────────────────────────────────────────

enum WsConnState { disconnected, connecting, connected }

class WebSyncState {
  const WebSyncState({
    this.state       = WsConnState.disconnected,
    this.deviceName,
    this.errorMsg,
  });
  final WsConnState state;
  final String?     deviceName;
  final String?     errorMsg;

  WebSyncState copyWith({
    WsConnState? state,
    String?      deviceName,
    String?      errorMsg,
  }) =>
      WebSyncState(
        state:      state      ?? this.state,
        deviceName: deviceName ?? this.deviceName,
        errorMsg:   errorMsg   ?? this.errorMsg,
      );
}

// ── Provider ───────────────────────────────────────────────────────────────

/// Manages the browser-side WebSocket connection to the phone.
/// Only used when running as a Flutter web app inside a browser.
class WebSyncNotifier extends StateNotifier<WebSyncState> {
  WebSyncNotifier() : super(const WebSyncState());

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;

  Future<void> connect(String wsUrl, String token) async {
    if (state.state == WsConnState.connecting ||
        state.state == WsConnState.connected) { return; }

    state = state.copyWith(state: WsConnState.connecting);

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone:  _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      // Send AUTH immediately.
      _channel!.sink.add(jsonEncode({'type': 'AUTH', 'token': token}));
    } catch (e) {
      state = state.copyWith(
        state:    WsConnState.disconnected,
        errorMsg: 'Connection failed: $e',
      );
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg  = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = (msg['type'] as String? ?? '').toUpperCase();
      switch (type) {
        case 'AUTH_OK':
          state = state.copyWith(
            state:      WsConnState.connected,
            deviceName: msg['device_name'] as String?,
          );
        case 'AUTH_FAIL':
          state = state.copyWith(
            state:    WsConnState.disconnected,
            errorMsg: 'Authentication failed — scan a new QR code',
          );
          disconnect();
        case 'PING':
          _channel?.sink.add(jsonEncode({'type': 'PONG'}));
        default:
          // ROWS, PUSH etc. handled by data notifiers (future implementation).
          break;
      }
    } catch (e) {
      debugPrint('[WebSync] Message parse error: $e');
    }
  }

  void _onDisconnected() {
    state = state.copyWith(
      state:    WsConnState.disconnected,
      deviceName: null,
    );
  }

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _onDisconnected();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

final webSyncProvider =
    StateNotifierProvider<WebSyncNotifier, WebSyncState>(
  (_) => WebSyncNotifier(),
);
