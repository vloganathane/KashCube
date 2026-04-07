import 'dart:async' as async_dart;

import 'package:dart_libp2p/dart_libp2p.dart';
import 'package:dart_libp2p/config/config.dart' as libp2p_config;
import 'package:dart_libp2p/config/defaults.dart' show defaultMuxers;
import 'package:dart_libp2p/p2p/transport/tcp_transport.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as conn_mgr;
import 'package:dart_libp2p/p2p/host/resource_manager/resource_manager_impl.dart';
import 'package:dart_libp2p/p2p/host/resource_manager/limiter.dart';
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
  Host? _host;

  /// Active protocol handlers (protocol ID → handler function)
  final Map<String, StreamHandler> _protocolHandlers = {};

  /// Active streams (peer ID → list of streams)
  final Map<String, List<P2PStream>> _activeStreams = {};

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
      // Generate or import Ed25519 key pair
      final keyPair = identity != null
          ? await generateEd25519KeyPairFromSeed(identity)
          : await generateEd25519KeyPair();

      // Create resource manager for connection limits
      final resourceManager = ResourceManagerImpl(limiter: FixedLimiter());

      // Create connection manager
      final connectionManager = conn_mgr.ConnectionManager();

      // Create TCP transport
      final tcpTransport = TCPTransport(
        resourceManager: resourceManager,
        connManager: connectionManager,
      );

      // Create Noise security protocol
      final noiseSecurity = await NoiseSecurity.create(keyPair);

      // Create config with options
      final config = libp2p_config.Config();
      final options = <libp2p_config.Option>[
        libp2p_config.Libp2p.identity(keyPair),
        libp2p_config.Libp2p.transport(tcpTransport),
        libp2p_config.Libp2p.security(noiseSecurity),
        libp2p_config.Libp2p.listenAddrs(
          (listenAddrs ?? ['/ip4/0.0.0.0/tcp/0'])
              .map((addr) => MultiAddr(addr))
              .toList(),
        ),
        defaultMuxers, // Yamux stream multiplexer
      ];

      await config.apply(options);
      _host = await config.newNode();

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
      // Start the host (begins listening on configured addresses)
      await _host!.start();

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
  /// The handler receives a [P2PStream] and [PeerId] and should read/write to the stream.
  /// The stream is automatically added to [_activeStreams] and removed when closed.
  void registerProtocol(String protocolId, StreamHandler handler) {
    if (!_initialized) {
      throw StateError('Must initialize before registering protocols');
    }

    _protocolHandlers[protocolId] = handler;

    // Register with dart_libp2p host
    // Note: ProtocolID is a String typedef
    _host!.setStreamHandler(protocolId, (P2PStream stream, PeerId remotePeer) async {
      final peerIdStr = remotePeer.toString();
      _trackStream(peerIdStr, stream);
      
      try {
        await handler(stream, remotePeer);
      } catch (e) {
        debugPrint('[LibP2pNode] Protocol handler error for $protocolId: $e');
        rethrow;
      } finally {
        _untrackStream(peerIdStr, stream);
      }
    });

    debugPrint('[LibP2pNode] Registered protocol: $protocolId');
  }

  /// Unregister a protocol handler.
  void unregisterProtocol(String protocolId) {
    if (_protocolHandlers.remove(protocolId) != null) {
      _host!.removeStreamHandler(protocolId);
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
  Future<P2PStream> dial(String peerMultiaddr, {required String protocolId}) async {
    if (!_started) {
      throw StateError('Must call start() before dialing');
    }

    try {
      debugPrint('[LibP2pNode] Dialing $peerMultiaddr with protocol $protocolId');

      // Parse multiaddr
      final addr = MultiAddr(peerMultiaddr);
      
      // Extract peer ID from multiaddr (/p2p/QmXXX component)
      final peerId = _extractPeerIdFromMultiaddr(addr);

      // Connect to peer (establishes connection if not already connected)
      final addrInfo = AddrInfo(peerId, [addr]);
      await _host!.connect(addrInfo);

      // Open stream with protocol negotiation
      //Note: ProtocolID is a String typedef, pass it directly
      final context = Context(); // Use default context
      final stream = await _host!.newStream(peerId, [protocolId], context);

      // Track stream
      final peerIdStr = peerId.toString();
      _trackStream(peerIdStr, stream);
      
      // Emit connection event
      _connectionEvents.add(PeerConnectionEvent(
        peerId: peerIdStr,
        type: PeerConnectionEventType.connected,
        timestamp: DateTime.now(),
      ));

      debugPrint('[LibP2pNode] Successfully dialed $peerIdStr on protocol $protocolId');
      return stream;
    } catch (e, stack) {
      debugPrint('[LibP2pNode] Dial failed: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  /// Extract PeerId from multiaddr.
  ///
  /// Multiaddr format: /ip4/192.168.1.10/tcp/9090/p2p/QmPeerId...
  PeerId _extractPeerIdFromMultiaddr(MultiAddr addr) {
    final peerIdValue = addr.valueForProtocol('p2p');
    if (peerIdValue == null || peerIdValue.isEmpty) {
      throw FormatException('No peer ID in multiaddr: $addr');
    }
    return PeerId.fromString(peerIdValue);
  }

  /// Send data on an existing stream.
  ///
  /// [stream]: Open libp2p stream
  /// [data]: Bytes to send
  ///
  /// Returns number of bytes written.
  Future<int> send(P2PStream stream, Uint8List data) async {
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

  /// Track an active stream.
  void _trackStream(String peerId, P2PStream stream) {
    _activeStreams.putIfAbsent(peerId, () => []).add(stream);
    debugPrint('[LibP2pNode] Tracking stream to $peerId (${_activeStreams[peerId]!.length} total)');
  }

  /// Untrack a closed stream.
  void _untrackStream(String peerId, P2PStream stream) {
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
