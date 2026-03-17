import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads length-prefixed JSON frames from a TCP [Socket].
///
/// Wire format: `[4-byte big-endian int32 = body length][UTF-8 JSON body]`
///
/// Maintains a **single** stream subscription for the lifetime of the
/// connection, avoiding Dart's "Stream has already been listened to" error
/// that occurs when [Socket.listen] is called more than once on the same
/// single-subscription stream.
///
/// Multiple sequential callers are supported via a FIFO waiter queue.
/// Any leftover bytes after extracting one frame are carried over into the
/// next [readMessage] call automatically.
class FrameReader {
  FrameReader(Socket socket) {
    _sub = socket.cast<Uint8List>().listen(
      _onData,
      onError: (_) => _teardown(),
      onDone: _teardown,
    );
  }

  late final StreamSubscription<Uint8List> _sub;

  // Bytes received but not yet consumed into a complete frame.
  final _buf = BytesBuilder(copy: false);

  // Expected body length once the 4-byte length header has been parsed.
  int? _expectedLength;

  // FIFO queue of callers waiting for the next complete frame.
  final _waiters = Queue<Completer<Map<String, dynamic>?>>();

  bool _closed = false;

  // ── Internal ─────────────────────────────────────────────────────────────

  void _onData(Uint8List chunk) {
    _buf.add(chunk);
    _drain();
  }

  /// Attempts to deliver one complete frame to the next waiter.
  void _drain() {
    while (_waiters.isNotEmpty) {
      final bytes = _buf.toBytes();

      // Parse the 4-byte header if we haven't yet.
      if (_expectedLength == null) {
        if (bytes.length < 4) return; // need more bytes
        _expectedLength = ByteData.sublistView(bytes, 0, 4).getInt32(0);
      }

      final total = 4 + _expectedLength!;
      if (bytes.length < total) return; // need more bytes for the body

      // Extract the frame body and keep any leftover bytes for the next frame.
      final body     = bytes.sublist(4, total);
      final leftover = bytes.sublist(total);
      _buf.clear();
      if (leftover.isNotEmpty) _buf.add(leftover);
      _expectedLength = null;

      final c = _waiters.removeFirst();
      try {
        c.complete(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      } catch (_) {
        c.complete(null);
      }
    }
  }

  void _teardown() {
    _closed = true;
    for (final c in _waiters) {
      if (!c.isCompleted) c.complete(null);
    }
    _waiters.clear();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Awaits the next complete frame.
  ///
  /// Returns `null` on timeout, connection close, or JSON parse error.
  Future<Map<String, dynamic>?> readMessage({
    Duration timeout = const Duration(seconds: 60),
  }) {
    if (_closed) return Future.value(null);
    final c = Completer<Map<String, dynamic>?>();
    _waiters.add(c);
    _drain(); // deliver immediately if bytes are already buffered
    return c.future.timeout(timeout, onTimeout: () {
      _waiters.remove(c);
      if (!c.isCompleted) c.complete(null);
      return null;
    });
  }

  /// Cancels the subscription and completes any pending readers with `null`.
  void dispose() {
    _sub.cancel();
    _teardown();
  }
}
