import 'dart:async' as async_dart;

import 'package:dart_libp2p/dart_libp2p.dart' as libp2p;
import 'package:flutter/foundation.dart';

/// Lifecycle wrapper for dart_libp2p Host.
///
/// Manages the libp2p Host instance with proper initialization, startup,
/// connection management, and graceful shutdown. Provides a simplified API
/// for KashCube sync use cases.
///
/// Usage:
/// ```dart
/// final node = LibP2pNode();
/// await node.initialize(identity: myIdentity);
/// await node.start();
/// final stream = await node.dial(peerMultiaddr, protocolId: '/kash-sync/1.0.0');
/// await node.close();
/// ```
class LibP2pNode {
  /// dart_libp2p Host instance (null until [initialize] is called)
  libp2p.Host? _host;

  /// Active protocol handlers (protocol ID → handler function)
  final Map<String, libp2p.StreamHandler> _protocolHandlers = {};

  /// Active streams (peer ID → list of streams)
  /// Note: Using dynamic until dart_libp2p Stream type is confirmed
  final Map<String, List<dynamic>> _activeStreams = {};

  /// Initialization state
  bool _initialized = false;
  bool _started = false;

  /// Controller for connection events
  final async_dart.StreamController<PeerConnectionEvent> _connectionEvents =
      async_dart.StreamController<PeerConnectionEvent>.broadcast();

  /// Expose connection events (peer connected, disconnected)
  async_dart.Stream<PeerConnectionEvent> get connectionEvents =>
      _connectionEvents.stream;

  /// Check if node is initialized
  bool get isInitialized => _initialized;

  /// Check if node is started (listening)
  bool get isStarted => _started;

  /// Get local peer ID (null if not initialized)
  String? get localPeerId => _host?.id.toString();

  /// Get listening addresses (empty if not started)
  List<String> get listeningAddrs {
    if (_host == null) return [];
    try {
      return _host!.addrs.map((addr) => addr.toString()).toList();
    } catch (e) {
      debugPrint('[LibP2pNode] Error getting addrs: $e');
      return [];
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  /// Initialize the libp2p host with optional identity.
  ///
  /// [identity]: Ed25519 private key seed (32 bytes). If null, generates new identity.
  /// [listenAddrs]: Multiaddrs to listen on (defaults to TCP on random port).
  ///
  /// Throws if already initialized.
  Future<void> initialize({
    Uint8List? identity,
    List<String>? listenAddrs,
  }) async {
    if (_initialized) {
      throw StateError('LibP2pNode already initialized');
    }

    try {
      // Create libp2p host
      // Note: Actual dart_libp2p API may differ - this is placeholder based on
      // typical libp2p patterns. Will need to adjust based on actual package API.
      _host = await _createHost(
        identity: identity,
        listenAddrs: listenAddrs ?? ['/ip4/0.0.0.0/tcp/0'],
      );

      _initialized = true;
      debugPrint('[LibP2pNode] Initialized with peer ID: ${_host!.id}');
    } catch (e, stack) {
      debugPrint('[LibP2pNode] Initialization failed: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  /// Start the libp2p host (begin listening for connections).
  ///
  /// Must call [initialize] first.
  /// Throws if not initialized or already started.
  Future<void> start() async {
    if (!_initialized) {
      throw StateError('Must call initialize() before start()');
    }
    if (_started) {
      throw StateError('LibP2pNode already started');
    }

    try {
      // Start listening (dart_libp2p specific API - placeholder)
      // await _host!.start();

      _started = true;
      debugPrint('[LibP2pNode] Started listening on: ${listeningAddrs.join(", ")}');
    } catch (e, stack) {
      debugPrint('[LibP2pNode] Start failed: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  /// Close the libp2p host and all active connections.
  ///
  /// Gracefully closes all streams, removes protocol handlers, and shuts down host.
  Future<void> close() async {
    if (!_initialized) return;

    debugPrint('[LibP2pNode] Closing...');

    try {
      // Close all active streams
      for (final streams in _activeStreams.values) {
        for (final stream in streams) {
          try {
            await stream.close();
          } catch (e) {
            debugPrint('[LibP2pNode] Error closing stream: $e');
          }
        }
      }
      _activeStreams.clear();

      // Remove all protocol handlers
      _protocolHandlers.clear();

      // Close host
      if (_host != null) {
        await _host!.close();
      }

      _initialized = false;
      _started = false;

      debugPrint('[LibP2pNode] Closed');
    } catch (e, stack) {
      debugPrint('[LibP2pNode] Close error: $e');
      debugPrint(stack.toString());
    } finally {
      await _connectionEvents.close();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Protocol Registration
  // ────────────────────────────────────────────────────────────────────────────

  /// Register a protocol handler.
  ///
  /// [protocolId]: Protocol identifier (e.g., "/kash-sync/1.0.0")
  /// [handler]: Function to handle incoming streams for this protocol
  ///
  /// The handler receives a [libp2p.Stream] and should read/write to it.
  /// The stream is automatically added to [_activeStreams] and removed when closed.
  void registerProtocol(String protocolId, libp2p.StreamHandler handler) {
    if (!_initialized) {
      throw StateError('Must initialize before registering protocols');
    }

    _protocolHandlers[protocolId] = handler;

    // Register with dart_libp2p host (placeholder - actual API may differ)
    // _host!.setStreamHandler(protocolId, (stream) async {
    //   _trackStream(stream.conn.remotePeer.toString(), stream);
    //   await handler(stream);
    //   _untrackStream(stream.conn.remotePeer.toString(), stream);
    // });

    debugPrint('[LibP2pNode] Registered protocol: $protocolId');
  }

  /// Unregister a protocol handler.
  void unregisterProtocol(String protocolId) {
    if (_protocolHandlers.remove(protocolId) != null) {
      // Unregister from dart_libp2p host (placeholder)
      // _host!.removeStreamHandler(protocolId);
      debugPrint('[LibP2pNode] Unregistered protocol: $protocolId');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Connection Management
  // ────────────────────────────────────────────────────────────────────────────

  /// Dial a peer and open a stream with the specified protocol.
  ///
  /// [peerMultiaddr]: Full multiaddr including peer ID (e.g., "/ip4/192.168.1.10/tcp/9090/p2p/QmPeerId...")
  /// [protocolId]: Protocol to negotiate (e.g., "/kash-sync/1.0.0")
  ///
  /// Returns the opened stream. Caller is responsible for reading/writing to the stream.
  /// The stream is automatically tracked and removed when closed.
  Future<dynamic> dial(String peerMultiaddr, {required String protocolId}) async {
    if (!_started) {
      throw StateError('Must call start() before dialing');
    }

    try {
      debugPrint('[LibP2pNode] Dialing $peerMultiaddr with protocol $protocolId');

      // Parse multiaddr (dart_libp2p API - placeholder)
      // final addr = libp2p.Multiaddr(peerMultiaddr);

      // Open stream with protocol negotiation (placeholder)
      // final stream = await _host!.newStream(addr.peerId, [protocolId]);

      // For now, throw not implemented
      throw UnimplementedError('Dial not yet implemented - awaiting dart_libp2p API integration');

      // Track stream
      // final peerId = addr.peerId.toString();
      // _trackStream(peerId, stream);
      
      // Emit connection event
      // _connectionEvents.add(PeerConnectionEvent(
      //   peerId: peerId,
      //   type: PeerConnectionEventType.connected,
      //   timestamp: DateTime.now(),
      // ));

      // return stream;
    } catch (e, stack) {
      debugPrint('[LibP2pNode] Dial failed: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  /// Send data on an existing stream.
  ///
  /// [stream]: Open libp2p stream
  /// [data]: Bytes to send
  ///
  /// Returns number of bytes written.
  Future<int> send(dynamic stream, Uint8List data) async {
    try {
      await stream.write(data);
      return data.length;
    } catch (e) {
      debugPrint('[LibP2pNode] Send error: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ────────────────────────────────────────────────────────────────────────────

  /// Create libp2p host instance.
  ///
  /// This is a placeholder - actual implementation depends on dart_libp2p API.
  Future<libp2p.Host> _createHost({
    Uint8List? identity,
    required List<String> listenAddrs,
  }) async {
    // Placeholder: Will need to implement based on actual dart_libp2p API
    // Example (may not match actual API):
    //
    // final privKey = identity != null
    //     ? await libp2p.PrivKey.fromEd25519Seed(identity)
    //     : await libp2p.PrivKey.generateEd25519();
    //
    // final host = await libp2p.Host.create(
    //   privateKey: privKey,
    //   listenAddrs: listenAddrs.map((a) => libp2p.Multiaddr(a)).toList(),
    //   transports: [libp2p.TCPTransport(), libp2p.UDXTransport()],
    //   security: [libp2p.Noise()],
    //   muxer: [libp2p.Yamux()],
    // );
    //
    // return host;

    throw UnimplementedError(
      'Host creation not yet implemented - '
      'awaiting dart_libp2p API integration. '
      'This is a Phase 1.3 placeholder.',
    );
  }

  /// Track an active stream.
  void _trackStream(String peerId, dynamic stream) {
    _activeStreams.putIfAbsent(peerId, () => []).add(stream);
    debugPrint('[LibP2pNode] Tracking stream to $peerId (${_activeStreams[peerId]!.length} total)');
  }

  /// Untrack a closed stream.
  void _untrackStream(String peerId, dynamic stream) {
    final streams = _activeStreams[peerId];
    if (streams != null) {
      streams.remove(stream);
      if (streams.isEmpty) {
        _activeStreams.remove(peerId);
        _connectionEvents.add(PeerConnectionEvent(
          peerId: peerId,
          type: PeerConnectionEventType.disconnected,
          timestamp: DateTime.now(),
        ));
      }
    }
    debugPrint('[LibP2pNode] Untracked stream to $peerId');
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Data Classes
// ──────────────────────────────────────────────────────────────────────────────

/// Type of peer connection event.
enum PeerConnectionEventType {
  connected,
  disconnected,
}

/// Event emitted when peer connection state changes.
class PeerConnectionEvent {
  const PeerConnectionEvent({
    required this.peerId,
    required this.type,
    required this.timestamp,
  });

  final String peerId;
  final PeerConnectionEventType type;
  final DateTime timestamp;

  @override
  String toString() => 'PeerConnectionEvent($type, peer=$peerId, at=$timestamp)';
}
