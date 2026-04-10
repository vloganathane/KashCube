/// Quality metrics for a peer connection.
///
/// Tracks connection reliability, latency, and success rate to enable
/// intelligent peer prioritization and connection management.
///
/// **Phase 4**: Used for peer scoring and eviction decisions.
class PeerQuality {
  /// Total connection attempts
  int connectionAttempts = 0;

  /// Successful connections
  int successfulConnections = 0;

  /// Failed connections
  int failedConnections = 0;

  /// Total messages sent
  int messagesSent = 0;

  /// Messages that failed to send
  int messagesFailed = 0;

  /// Average round-trip time for PING/PONG (milliseconds)
  double averageLatencyMs = 0.0;

  /// Last 10 latency samples for moving average
  final List<int> _latencySamples = [];

  /// Last successful connection time
  DateTime? lastConnected;

  /// Last disconnect time
  DateTime? lastDisconnected;

  /// Total time connected (accumulated)
  Duration totalUptime = Duration.zero;

  /// Connection start time (for current session)
  DateTime? _connectionStart;

  PeerQuality();

  /// Calculate success rate (0.0 to 1.0).
  double get successRate {
    if (connectionAttempts == 0) return 0.0;
    return successfulConnections / connectionAttempts;
  }

  /// Calculate message delivery rate (0.0 to 1.0).
  double get messageDeliveryRate {
    if (messagesSent == 0) return 1.0; // No data yet, optimistic
    final successful = messagesSent - messagesFailed;
    return successful / messagesSent;
  }

  /// Overall quality score (0.0 to 100.0).
  ///
  /// Weighted formula:
  /// - 40% success rate
  /// - 30% message delivery rate
  /// - 20% latency (lower is better, normalized)
  /// - 10% uptime ratio
  double get qualityScore {
    // Success rate component (0-40 points)
    final successComponent = successRate * 40.0;

    // Message delivery component (0-30 points)
    final deliveryComponent = messageDeliveryRate * 30.0;

    // Latency component (0-20 points, inverse: lower latency = higher score)
    // Assume 500ms is poor, 0ms is perfect
    final normalizedLatency = (500.0 - averageLatencyMs.clamp(0.0, 500.0)) / 500.0;
    final latencyComponent = normalizedLatency * 20.0;

    // Uptime component (0-10 points)
    // Prefer peers with more uptime
    final uptimeSeconds = totalUptime.inSeconds;
    final uptimeComponent = (uptimeSeconds / 3600.0).clamp(0.0, 1.0) * 10.0;

    return successComponent + deliveryComponent + latencyComponent + uptimeComponent;
  }

  /// Record a connection attempt.
  void recordConnectionAttempt() {
    connectionAttempts++;
  }

  /// Record a successful connection.
  void recordConnectionSuccess() {
    successfulConnections++;
    lastConnected = DateTime.now();
    _connectionStart = DateTime.now();
  }

  /// Record a failed connection.
  void recordConnectionFailure() {
    failedConnections++;
  }

  /// Record a disconnect and accumulate uptime.
  void recordDisconnect() {
    lastDisconnected = DateTime.now();

    if (_connectionStart != null) {
      final sessionDuration = DateTime.now().difference(_connectionStart!);
      totalUptime += sessionDuration;
      _connectionStart = null;
    }
  }

  /// Record a message send attempt.
  void recordMessageSent() {
    messagesSent++;
  }

  /// Record a message send failure.
  void recordMessageFailure() {
    messagesFailed++;
  }

  /// Record a latency sample (PING/PONG round-trip time in ms).
  void recordLatency(int latencyMs) {
    _latencySamples.add(latencyMs);

    // Keep only last 10 samples (moving average)
    if (_latencySamples.length > 10) {
      _latencySamples.removeAt(0);
    }

    // Recalculate average
    if (_latencySamples.isNotEmpty) {
      final sum = _latencySamples.reduce((a, b) => a + b);
      averageLatencyMs = sum / _latencySamples.length;
    }
  }

  /// Check if peer is healthy (recent activity).
  bool isHealthy(Duration timeout) {
    if (lastConnected == null) return false;
    final now = DateTime.now();
    return now.difference(lastConnected!) < timeout;
  }

  /// Get a human-readable quality rating.
  String get qualityRating {
    final score = qualityScore;
    if (score >= 80.0) return 'Excellent';
    if (score >= 60.0) return 'Good';
    if (score >= 40.0) return 'Fair';
    if (score >= 20.0) return 'Poor';
    return 'Very Poor';
  }

  @override
  String toString() {
    return 'PeerQuality('
        'score: ${qualityScore.toStringAsFixed(1)}, '
        'success: ${(successRate * 100).toStringAsFixed(0)}%, '
        'latency: ${averageLatencyMs.toStringAsFixed(0)}ms, '
        'uptime: ${totalUptime.inMinutes}m)';
  }
}
