import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'libp2p_node.dart';
import 'libp2p_protocol.dart';

/// Direct broadcast layer for libp2p mesh network.
///
/// Implements topic-based broadcasting by sending messages directly to all
/// connected peers. Unlike gossipsub (which uses peer gossip for propagation),
/// this uses direct sends for simplicity and privacy.
///
/// **Why not gossipsub?**
/// - dart_libp2p v1.0.3 doesn't include gossipsub yet
/// - KashCube is LAN-only with max 10 peers (direct broadcast scales fine)
/// - Privacy-first: no need for gossip propagation across internet
/// - Simpler: direct send to all peers is easier to debug and maintain
///
/// **Upgrade path**: When dart_libp2p adds gossipsub, we can swap this out
/// while keeping the same public API (subscribe, publish, unsubscribe).
class LibP2pBroadcast {
  final LibP2pNode _node;
  final LibP2pProtocol _protocol;
  final Map<String, dynamic> _peerStreams; // Reference to repository's streams

  /// Topic subscriptions: topic → list of message handlers
  final Map<String, List<MessageHandler>> _subscriptions = {};

  /// Message deduplication cache: msgId → timestamp
  /// Messages are cached for 24 hours to prevent duplicate processing
  final LinkedHashMap<String, DateTime> _seenMessages =
      LinkedHashMap<String, DateTime>();
  static const int _maxSeenMessages = 10000; // Bounded cache
  static const Duration _seenTtl = Duration(hours: 24);

  /// Stream controller for incoming messages (all topics)
  final StreamController<TopicMessage> _messageController =
      StreamController<TopicMessage>.broadcast();

  /// Expose incoming messages stream
  Stream<TopicMessage> get messages => _messageController.stream;

  LibP2pBroadcast({
    required LibP2pNode node,
    required LibP2pProtocol protocol,
    required Map<String, dynamic> peerStreams,
  }) : _node = node,
       _protocol = protocol,
       _peerStreams = peerStreams;

  // ────────────────────────────────────────────────────────────────────────────
  // Public API (Topic Management)
  // ────────────────────────────────────────────────────────────────────────────

  /// Subscribe to a topic with a message handler.
  ///
  /// When a message arrives on [topic], [handler] will be called.
  /// Multiple handlers can subscribe to the same topic.
  ///
  /// Returns a subscription that can be cancelled.
  StreamSubscription<TopicMessage> subscribe(
    String topic,
    MessageHandler handler,
  ) {
    debugPrint('[LibP2pBroadcast] Subscribing to topic: $topic');

    // Add handler to topic subscriptions
    _subscriptions.putIfAbsent(topic, () => []);
    _subscriptions[topic]!.add(handler);

    // Listen to messages stream and filter by topic
    return _messageController.stream
        .where((msg) => msg.topic == topic)
        .listen(handler);
  }

  /// Unsubscribe from a topic (removes all handlers for that topic).
  void unsubscribe(String topic) {
    debugPrint('[LibP2pBroadcast] Unsubscribing from topic: $topic');
    _subscriptions.remove(topic);
  }

  /// Publish a message to a topic.
  ///
  /// Sends the message directly to all connected peers. Each peer will:
  /// 1. Check if message was already seen (dedupe)
  /// 2. Process message if subscribed to topic
  /// 3. Re-broadcast to their peers (creates mesh propagation)
  ///
  /// [topic]: Topic name (e.g., '/kash-sync/1.0.0')
  /// [data]: Message payload (must be JSON-serializable)
  /// [msgId]: Optional message ID for deduplication (generated if null)
  Future<void> publish({
    required String topic,
    required Map<String, dynamic> data,
    String? msgId,
  }) async {
    // Generate message ID if not provided
    msgId ??= _generateMessageId();

    // Check if we've already seen this message (prevent loops)
    if (_isMessageSeen(msgId)) {
      debugPrint('[LibP2pBroadcast] Skipping duplicate message: $msgId');
      return;
    }

    // Mark as seen
    _markMessageSeen(msgId);

    // Create message envelope
    final message = {
      'msgId': msgId,
      'topic': topic,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    debugPrint(
      '[LibP2pBroadcast] Publishing to $topic from ${_node.localPeerId} '
      '(${_peerStreams.length} peers): $msgId',
    );

    // Broadcast to all connected peers
    final futures = <Future>[];
    for (final peerId in _peerStreams.keys.toList()) {
      futures.add(_sendToPeer(peerId, message));
    }

    // Wait for all sends (fire-and-forget, don't block on failures)
    await Future.wait(futures, eagerError: false);
  }

  /// Handle incoming message from peer.
  ///
  /// Called by repository when a BROADCAST frame is received.
  /// Deduplicates, processes locally, and re-broadcasts to create mesh propagation.
  Future<void> handleIncomingMessage(Map<String, dynamic> message) async {
    final msgId = message['msgId'] as String?;
    final topic = message['topic'] as String?;
    final data = message['data'] as Map<String, dynamic>?;

    if (msgId == null || topic == null || data == null) {
      debugPrint('[LibP2pBroadcast] Invalid message format, ignoring');
      return;
    }

    // Deduplication: ignore if already seen
    if (_isMessageSeen(msgId)) {
      debugPrint('[LibP2pBroadcast] Ignoring duplicate message: $msgId');
      return;
    }

    // Mark as seen BEFORE processing (prevents re-broadcast loops)
    _markMessageSeen(msgId);

    debugPrint('[LibP2pBroadcast] Received message on $topic: $msgId');

    // Emit to local subscribers
    final topicMessage = TopicMessage(
      msgId: msgId,
      topic: topic,
      data: data,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        message['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );

    if (!_messageController.isClosed) {
      _messageController.add(topicMessage);
    }

    // Re-broadcast to other peers (creates mesh propagation)
    // This ensures messages reach all peers even if not directly connected
    await _rebroadcast(message);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ────────────────────────────────────────────────────────────────────────────

  /// Send message to specific peer (fire-and-forget).
  Future<void> _sendToPeer(String peerId, Map<String, dynamic> message) async {
    try {
      final stream = _peerStreams[peerId];
      if (stream == null) {
        debugPrint('[LibP2pBroadcast] No stream for peer $peerId, skipping');
        return;
      }

      // Wrap in BROADCAST frame for protocol
      final frame = {'type': 'BROADCAST', 'message': message};

      // Send using LibP2pProtocol (length-prefixed JSON)
      await _protocol.sendFrame(stream, frame);

      debugPrint('[LibP2pBroadcast] Sent message to $peerId');
    } catch (e, stack) {
      debugPrint('[LibP2pBroadcast] Error sending to $peerId: $e');
      debugPrint(stack.toString());
      // Don't rethrow - continue broadcasting to other peers
    }
  }

  /// Re-broadcast message to all peers except the sender.
  ///
  /// Creates mesh propagation: when Peer A sends to Peer B, B re-broadcasts
  /// to C, D, E, ensuring everyone receives it even if not directly connected.
  Future<void> _rebroadcast(Map<String, dynamic> message) async {
    // TODO: Track message sender to avoid sending back to them
    // For now, dedupe handles this (sender already saw the message)

    final futures = <Future>[];
    for (final peerId in _peerStreams.keys.toList()) {
      futures.add(_sendToPeer(peerId, message));
    }

    await Future.wait(futures, eagerError: false);
  }

  /// Check if message was already seen (deduplication).
  bool _isMessageSeen(String msgId) {
    // Clean old entries first (TTL expired)
    _cleanSeenCache();
    return _seenMessages.containsKey(msgId);
  }

  /// Mark message as seen with current timestamp.
  void _markMessageSeen(String msgId) {
    _seenMessages[msgId] = DateTime.now();

    // Bounded cache: evict oldest if too large
    if (_seenMessages.length > _maxSeenMessages) {
      final oldestKey = _seenMessages.keys.first;
      _seenMessages.remove(oldestKey);
    }
  }

  /// Clean expired entries from seen cache (older than TTL).
  void _cleanSeenCache() {
    final now = DateTime.now();
    _seenMessages.removeWhere((msgId, timestamp) {
      return now.difference(timestamp) > _seenTtl;
    });
  }

  /// Generate unique message ID (timestamp + random).
  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 100000;
    return '$timestamp-$random';
  }

  /// Close broadcast layer and clean up resources.
  void close() {
    debugPrint('[LibP2pBroadcast] Closing broadcast layer');
    _subscriptions.clear();
    _seenMessages.clear();
    _messageController.close();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Data Classes
// ────────────────────────────────────────────────────────────────────────────

/// Message received on a topic.
class TopicMessage {
  final String msgId;
  final String topic;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  TopicMessage({
    required this.msgId,
    required this.topic,
    required this.data,
    required this.timestamp,
  });

  @override
  String toString() => 'TopicMessage($topic: $msgId)';
}

/// Handler function for topic messages.
typedef MessageHandler = void Function(TopicMessage message);
