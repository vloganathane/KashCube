import 'dart:async' as async_dart;
import 'dart:convert';

import 'package:dart_libp2p/dart_libp2p.dart';
import 'package:flutter/foundation.dart';

/// Protocol ID for KashCube sync over libp2p.
const String kashSyncProtocolId = '/kash-sync/1.0.0';

/// Maximum frame size (1 MB default, configurable 64 KB - 10 MB).
const int defaultMaxFrameSize = 1048576; // 1 MB

/// Frame handler function signature.
///
/// Receives a parsed JSON frame and returns an optional response frame.
/// The response is sent back to the peer if non-null.
typedef FrameHandler = Future<Map<String, dynamic>?> Function(
  Map<String, dynamic> frame,
  String peerId,
);

/// Stream handler type alias for libp2p protocol streams.
/// Signature matches dart_libp2p StreamHandler: (P2PStream, PeerId) async function
typedef LibP2pStreamHandler = StreamHandler;

/// Handles the /kash-sync/1.0.0 protocol stream operations.
///
/// Responsibilities:
/// - Parse length-prefixed JSON frames from streams
/// - Route frame types to registered handlers
/// - Serialize and send response frames
/// - Handle protocol errors (malformed JSON, frame too large, etc.)
///
/// Frame format: 4-byte length prefix (big-endian u32) + JSON payload
///
/// Usage:
/// ```dart
/// final protocol = LibP2pProtocol();
/// protocol.registerHandler('SYNC_PLAN', (frame, peerId) async {
///   // Handle SYNC_PLAN frame
///   return {'type': 'WRITE_OK', 'table': frame['table'], 'count': 10};
/// });
/// final streamHandler = protocol.createStreamHandler();
/// node.registerProtocol('/kash-sync/1.0.0', streamHandler);
/// ```
class LibP2pProtocol {
  /// Frame type handlers (e.g., 'SYNC_PLAN', 'ROWS', 'PUSH', etc.)
  final Map<String, FrameHandler> _handlers = {};

  /// Maximum frame size (bytes)
  int maxFrameSize = defaultMaxFrameSize;

  /// Controller for received frames (for monitoring/debugging)
  final async_dart.StreamController<ReceivedFrame> _receivedFrames =
      async_dart.StreamController<ReceivedFrame>.broadcast();

  /// Expose received frames stream
  async_dart.Stream<ReceivedFrame> get receivedFrames => _receivedFrames.stream;

  // ────────────────────────────────────────────────────────────────────────────
  // Handler Registration
  // ────────────────────────────────────────────────────────────────────────────

  /// Register a handler for a specific frame type.
  ///
  /// [frameType]: Frame type key in JSON (e.g., 'SYNC_PLAN', 'ROWS', 'PUSH')
  /// [handler]: Function to handle frames of this type
  void registerHandler(String frameType, FrameHandler handler) {
    _handlers[frameType] = handler;
    debugPrint('[LibP2pProtocol] Registered handler for $frameType');
  }

  /// Unregister a handler for a frame type.
  void unregisterHandler(String frameType) {
    if (_handlers.remove(frameType) != null) {
      debugPrint('[LibP2pProtocol] Unregistered handler for $frameType');
    }
  }

  /// Clear all registered handlers.
  void clearHandlers() {
    _handlers.clear();
    debugPrint('[LibP2pProtocol] Cleared all handlers');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Stream Handler Factory
  // ────────────────────────────────────────────────────────────────────────────

  /// Create a libp2p stream handler for the /kash-sync/1.0.0 protocol.
  ///
  /// Returns a function that can be registered with [LibP2pNode.registerProtocol].
  /// The handler reads length-prefixed frames, parses JSON, routes to handlers,
  /// and sends responses.
  LibP2pStreamHandler createStreamHandler() {
    return (P2PStream stream, PeerId remotePeer) async {
      final peerId = remotePeer.toString();
      debugPrint('[LibP2pProtocol] Stream opened from $peerId');

      try {
        await _handleStream(stream, peerId);
      } catch (e, stack) {
        debugPrint('[LibP2pProtocol] Stream error from $peerId: $e');
        debugPrint(stack.toString());
        
        // Send ERROR frame if possible
        try {
          await _sendFrame(stream, {
            'type': 'ERROR',
            'code': 'STREAM_ERROR',
            'message': e.toString(),
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {
          // Ignore error sending error frame
        }
      } finally {
        try {
          await stream.close();
        } catch (e) {
          debugPrint('[LibP2pProtocol] Error closing stream: $e');
        }
        debugPrint('[LibP2pProtocol] Stream closed from $peerId');
      }
    };
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Stream Processing
  // ────────────────────────────────────────────────────────────────────────────

  /// Handle an open stream: read frames, route to handlers, send responses.
  ///
  /// Runs until stream is closed by either peer or error occurs.
  Future<void> _handleStream(P2PStream stream, String peerId) async {
    while (true) {
      try {
        // Read frame
        final frame = await _readFrame(stream);
        if (frame == null) {
          // EOF (stream closed by peer)
          debugPrint('[LibP2pProtocol] EOF from $peerId');
          break;
        }

        debugPrint('[LibP2pProtocol] Received ${frame['type']} from $peerId');

        // Emit received frame event
        _receivedFrames.add(ReceivedFrame(
          frame: frame,
          peerId: peerId,
          timestamp: DateTime.now(),
        ));

        // Route to handler
        final response = await _routeFrame(frame, peerId);

        // Send response if handler returned one
        if (response != null) {
          await _sendFrame(stream, response);
          debugPrint('[LibP2pProtocol] Sent ${response['type']} to $peerId');
        }
      } catch (e) {
        debugPrint('[LibP2pProtocol] Frame processing error: $e');
        
        // Send ERROR frame
        await _sendFrame(stream, {
          'type': 'ERROR',
          'code': 'FRAME_PROCESSING_ERROR',
          'message': e.toString(),
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        
        // Continue to next frame (don't break connection on single frame error)
      }
    }
  }

  /// Route a frame to the appropriate handler.
  ///
  /// Returns the handler's response frame, or null if no response.
  /// Throws if frame type is unknown.
  Future<Map<String, dynamic>?> _routeFrame(
    Map<String, dynamic> frame,
    String peerId,
  ) async {
    final frameType = frame['type'] as String?;
    if (frameType == null || frameType.isEmpty) {
      throw FormatException('Frame missing "type" field');
    }

    final handler = _handlers[frameType];
    if (handler == null) {
      throw StateError('No handler registered for frame type: $frameType');
    }

    return handler(frame, peerId);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Frame Serialization
  // ────────────────────────────────────────────────────────────────────────────

  /// Read a length-prefixed JSON frame from the stream.
  ///
  /// Frame format: 4-byte big-endian u32 length + JSON payload
  ///
  /// Returns null on EOF (stream closed).
  /// Throws on malformed data, oversized frames, or JSON parse errors.
  Future<Map<String, dynamic>?> _readFrame(P2PStream stream) async {
    // Read 4-byte length prefix
    final lengthBytes = await _readExact(stream, 4);
    if (lengthBytes == null) {
      return null; // EOF
    }

    // Parse length (big-endian u32)
    final length = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big).toInt();

    // Check frame size limit
    if (length > maxFrameSize) {
      throw StateError(
        'Frame too large: $length bytes (max: $maxFrameSize)',
      );
    }

    // Read JSON payload
    final payloadBytes = await _readExact(stream, length);
    if (payloadBytes == null || payloadBytes.length != length) {
      throw StateError('Incomplete frame: expected $length bytes');
    }

    // Parse JSON
    try {
      final json = utf8.decode(payloadBytes);
      final frame = jsonDecode(json) as Map<String, dynamic>;
      return frame;
    } catch (e) {
      throw FormatException('Invalid JSON in frame: $e');
    }
  }

  /// Send a JSON frame to the peer with length prefix.
  ///
  /// Frame format: 4-byte big-endian u32 length + JSON payload
  Future<void> _sendFrame(P2PStream stream, Map<String, dynamic> frame) async {
    // Serialize to JSON
    final json = jsonEncode(frame);
    final payloadBytes = utf8.encode(json);

    // Check frame size limit
    if (payloadBytes.length > maxFrameSize) {
      throw StateError(
        'Frame too large: ${payloadBytes.length} bytes (max: $maxFrameSize)',
      );
    }

    // Build length prefix (4-byte big-endian u32)
    final lengthBytes = Uint8List(4);
    ByteData.sublistView(lengthBytes).setUint32(0, payloadBytes.length, Endian.big);

    // Write length + payload
    await stream.write(Uint8List.fromList([...lengthBytes, ...payloadBytes]));
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Low-Level Stream I/O
  // ────────────────────────────────────────────────────────────────────────────

  /// Read exactly [n] bytes from stream.
  ///
  /// Returns null on EOF.
  /// Throws if stream closes before [n] bytes read.
  Future<Uint8List?> _readExact(P2PStream stream, int n) async {
    final buffer = Uint8List(n);
    int bytesRead = 0;

    while (bytesRead < n) {
      final chunk = await stream.read(n - bytesRead);
      if (chunk.isEmpty) {
        if (bytesRead == 0) {
          return null; // EOF at start
        }
        throw StateError('Stream closed mid-frame (read $bytesRead of $n bytes)');
      }

      final chunkLength = (chunk.length as num).toInt();
      buffer.setRange(bytesRead, bytesRead + chunkLength, chunk);
      bytesRead += chunkLength;
    }

    return buffer;
  }



  // ────────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ────────────────────────────────────────────────────────────────────────────

  /// Dispose of resources.
  Future<void> dispose() async {
    clearHandlers();
    await _receivedFrames.close();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Data Classes
// ──────────────────────────────────────────────────────────────────────────────

/// Represents a received frame (for monitoring/debugging).
class ReceivedFrame {
  const ReceivedFrame({
    required this.frame,
    required this.peerId,
    required this.timestamp,
  });

  final Map<String, dynamic> frame;
  final String peerId;
  final DateTime timestamp;

  String get frameType => frame['type'] as String? ?? 'UNKNOWN';

  @override
  String toString() => 'ReceivedFrame($frameType from $peerId at $timestamp)';
}
