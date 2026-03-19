import 'dart:async';

/// A per-process singleton event bus for SQLite table-change notifications.
///
/// Purpose
/// -------
/// Components that write to SQLite call [emit] with the affected table name.
/// The coordinator ([P2pCoordinator]) and the web-sync notifier
/// ([WebSyncNotifier]) subscribe to [stream] and trigger an immediate delta
/// flush instead of waiting for the next 30-second fallback timer tick.
///
/// Debounce
/// --------
/// Rapid bursts (e.g. bulk SMS import touching 'transactions' 200× in a
/// second) are collapsed into a single event per table per [debounceDuration].
/// The default 200 ms window is good enough for all interactive write paths.
///
/// Cross-process isolation
/// -----------------------
/// On the phone, this singleton lives in the native Flutter isolate.
/// In the browser, it lives in the WASM isolate. They are completely
/// independent — events never cross the network boundary (that is the
/// WebSocket's job).
class SyncEventBus {
  SyncEventBus._();
  static final SyncEventBus instance = SyncEventBus._();

  static const Duration debounceDuration = Duration(milliseconds: 200);

  final _controller = StreamController<String>.broadcast();

  /// Debounce timers keyed by table name.
  final Map<String, Timer> _debounce = {};

  /// Stream of table names that have had recent writes.
  ///
  /// Events are debounced — at most one event per table per [debounceDuration].
  Stream<String> get stream => _controller.stream;

  /// Notify that [table] has been modified.
  ///
  /// Multiple rapid calls for the same table are collapsed: the event is
  /// emitted only once, [debounceDuration] after the *last* call.
  void emit(String table) {
    _debounce[table]?.cancel();
    _debounce[table] = Timer(debounceDuration, () {
      _debounce.remove(table);
      if (!_controller.isClosed) {
        _controller.add(table);
      }
    });
  }

  /// Cancels all pending debounce timers and closes the stream.
  ///
  /// Only call during app teardown / test cleanup.
  void dispose() {
    for (final t in _debounce.values) {
      t.cancel();
    }
    _debounce.clear();
    _controller.close();
  }
}
