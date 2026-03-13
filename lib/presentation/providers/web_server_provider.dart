import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/web_server_service.dart';

/// State exposed to the UI.
class WebServerState {
  const WebServerState({
    this.isRunning = false,
    this.qrPayload,
    this.localUrl,
    this.port,
    this.error,
  });

  final bool isRunning;
  final String? qrPayload;
  final String? localUrl;
  final int? port;
  final String? error;

  WebServerState copyWith({
    bool? isRunning,
    String? qrPayload,
    String? localUrl,
    int? port,
    String? error,
  }) =>
      WebServerState(
        isRunning: isRunning ?? this.isRunning,
        qrPayload: qrPayload ?? this.qrPayload,
        localUrl: localUrl ?? this.localUrl,
        port: port ?? this.port,
        error: error,
      );
}

class WebServerNotifier extends StateNotifier<WebServerState> {
  WebServerNotifier() : super(const WebServerState());

  final _service = WebServerService.instance;

  Future<void> start() async {
    if (state.isRunning) return;
    state = const WebServerState(); // clear previous error
    try {
      // Load the bundled SPA so the server can serve it.
      String? spaHtml;
      try {
        spaHtml = await rootBundle.loadString('assets/web_ui/index.html');
      } catch (_) {
        // Falls back to inline HTML in WebServerService
      }

      await _service.start(spaHtml: spaHtml);

      state = WebServerState(
        isRunning: true,
        qrPayload: _service.qrPayload,
        localUrl: _service.localUrl,
        port: _service.port,
      );
    } catch (e) {
      state = WebServerState(error: 'Failed to start: $e');
    }
  }

  Future<void> stop() async {
    await _service.stop();
    state = const WebServerState();
  }

  Future<void> revokeSession() async {
    await _service.revokeSession();
    // Update QR payload — new token has been generated
    state = state.copyWith(qrPayload: _service.qrPayload);
  }
}

final webServerProvider =
    StateNotifierProvider<WebServerNotifier, WebServerState>(
  (ref) {
    final notifier = WebServerNotifier();
    ref.onDispose(notifier.stop);
    return notifier;
  },
);
