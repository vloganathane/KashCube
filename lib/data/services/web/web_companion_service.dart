import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../p2p/p2p_server.dart';
import 'web_ui_extractor.dart';

/// Manages the wake-lock lifecycle for the web companion ("Open on Laptop").
///
/// While a browser is actively connected to the phone's local LAN server this
/// service holds a [WakelockPlus] wake lock so the CPU stays awake and the
/// WebSocket connection remains stable — even when the user briefly minimises
/// KashCube to switch tabs or the screen dims.
///
/// The wake lock is released with a 30-second grace period after disconnect,
/// which tolerates transient drops (e.g. the browser does a page refresh).
///
/// Usage:
/// ```dart
/// // Call once at app startup, before runApp.
/// WebCompanionService.instance.attach();
///
/// // In app lifecycle observer:
/// @override
/// void didChangeAppLifecycleState(AppLifecycleState state) {
///   if (state == AppLifecycleState.paused)   WebCompanionService.instance.onAppPaused();
///   if (state == AppLifecycleState.resumed)  WebCompanionService.instance.onAppResumed();
/// }
/// ```
class WebCompanionService {
  WebCompanionService._();
  static final WebCompanionService instance = WebCompanionService._();

  StreamSubscription<bool>? _sub;
  Timer? _releaseTimer;
  bool _wakeLockHeld = false;

  /// True when the extracted web build is available locally.
  bool get isReady => WebUiExtractor.instance.isReady;

  /// Prepares the web bundle in temporary storage before the server accepts
  /// browser requests. Safe to call repeatedly.
  Future<void> prewarmWebUi() => WebUiExtractor.instance.extractNow();

  /// Subscribes to browser-connection events from [P2pServer].
  ///
  /// Idempotent — safe to call multiple times; subsequent calls are no-ops.
  /// Must be called before the server starts so no events are missed.
  void attach() {
    if (_sub != null) return;
    _sub = P2pServer.instance.browserConnectionStream.listen(_onBrowserEvent);
    // Sync with the current state: if a browser is already connected before
    // attach() is called (e.g. app restarted while browser tab is open),
    // acquire the wake lock immediately.
    if (P2pServer.instance.hasBrowserConnected) _acquireWakeLock();
    debugPrint('[WebCompanionService] Attached to browser connection stream');
  }

  void _onBrowserEvent(bool connected) {
    if (connected) {
      // Browser just authenticated — acquire immediately.
      _releaseTimer?.cancel();
      _releaseTimer = null;
      _acquireWakeLock();
    } else {
      // Delay release so page-refresh or brief network hiccup doesn't
      // unnecessarily cycle the wake lock.
      _releaseTimer?.cancel();
      _releaseTimer = Timer(const Duration(seconds: 30), _releaseWakeLock);
    }
  }

  /// Called from the app lifecycle observer when the app enters the background.
  ///
  /// If a browser is connected, the wake lock is (re-)acquired to prevent the
  /// CPU from dozing while the WebSocket must stay alive.
  void onAppPaused() {
    if (P2pServer.instance.hasBrowserConnected) {
      _acquireWakeLock();
    }
  }

  /// Called from the app lifecycle observer when the app returns to foreground.
  ///
  /// Releases the wake lock if no browser is connected (screen + CPU can now
  /// sleep normally between user interactions).
  void onAppResumed() {
    if (!P2pServer.instance.hasBrowserConnected) {
      _releaseWakeLock();
    }
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  void _acquireWakeLock() {
    if (_wakeLockHeld || kIsWeb) return;
    try {
      WakelockPlus.enable();
      _wakeLockHeld = true;
      debugPrint('[WebCompanionService] Wake lock acquired');
    } catch (e) {
      debugPrint('[WebCompanionService] Failed to acquire wake lock: $e');
    }
  }

  void _releaseWakeLock() {
    if (!_wakeLockHeld || kIsWeb) return;
    try {
      WakelockPlus.disable();
      _wakeLockHeld = false;
      debugPrint('[WebCompanionService] Wake lock released');
    } catch (e) {
      debugPrint('[WebCompanionService] Failed to release wake lock: $e');
    }
  }
}
