import 'package:flutter/foundation.dart';

/// Vector clock for distributed conflict detection.
///
/// Tracks logical time for each device in the mesh network using Lamport timestamps.
/// Enables detection of concurrent (conflicting) updates and causality ordering.
///
/// **Algorithm**: Each device maintains a counter. On local change:
/// 1. Increment own counter
/// 2. Include full vector clock in sync message
/// 3. On receive: merge (take max of each device's counter)
///
/// **Conflict detection**:
/// - VectorClock A dominates B if: A[i] >= B[i] for all i AND A != B
/// - A and B are concurrent if: neither dominates (conflict!)
///
/// **Example**:
/// ```dart
/// // Device A creates transaction
/// final clockA = VectorClock({'deviceA': 1, 'deviceB': 0});
///
/// // Device B creates transaction simultaneously
/// final clockB = VectorClock({'deviceA': 0, 'deviceB': 1});
///
/// // Conflict detection
/// clockA.happensBefore(clockB); // false
/// clockB.happensBefore(clockA); // false
/// clockA.isConcurrentWith(clockB); // true ← CONFLICT!
/// ```
@immutable
class VectorClock {
  /// Device ID → logical timestamp
  final Map<String, int> _clocks;

  /// Create vector clock from existing clocks map.
  const VectorClock(Map<String, int> clocks) : _clocks = clocks;

  /// Create empty vector clock.
  VectorClock.empty() : _clocks = {};

  /// Create vector clock from JSON.
  factory VectorClock.fromJson(Map<String, dynamic> json) {
    final clocks = <String, int>{};
    for (final entry in json.entries) {
      if (entry.value is int) {
        clocks[entry.key] = entry.value as int;
      }
    }
    return VectorClock(clocks);
  }

  /// Convert to JSON (for network serialization).
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_clocks);

  /// Get logical timestamp for a specific device.
  /// Returns 0 if device not in clock.
  int operator [](String deviceId) => _clocks[deviceId] ?? 0;

  /// Get all device IDs in this clock.
  Set<String> get deviceIds => _clocks.keys.toSet();

  /// Get number of devices tracked.
  int get size => _clocks.length;

  /// Increment the counter for a specific device.
  ///
  /// Returns a NEW VectorClock (immutable).
  VectorClock increment(String deviceId) {
    final newClocks = Map<String, int>.from(_clocks);
    newClocks[deviceId] = (newClocks[deviceId] ?? 0) + 1;
    return VectorClock(newClocks);
  }

  /// Merge with another vector clock (take max of each device's counter).
  ///
  /// This is used when receiving a message from another device:
  /// 1. Merge the received clock with local clock
  /// 2. Increment own counter
  ///
  /// Returns a NEW VectorClock (immutable).
  VectorClock merge(VectorClock other) {
    final newClocks = Map<String, int>.from(_clocks);

    // Take max of each device's timestamp
    for (final deviceId in other.deviceIds) {
      final ourTime = newClocks[deviceId] ?? 0;
      final theirTime = other[deviceId];
      newClocks[deviceId] = ourTime > theirTime ? ourTime : theirTime;
    }

    return VectorClock(newClocks);
  }

  /// Check if this clock happens before (is dominated by) another clock.
  ///
  /// A happens-before B if:
  /// - A[i] <= B[i] for all devices i
  /// - AND A != B (at least one device has lower timestamp in A)
  ///
  /// Returns true if this event causally precedes the other event.
  bool happensBefore(VectorClock other) {
    bool anyLess = false;

    // Check all devices in both clocks
    final allDevices = {...deviceIds, ...other.deviceIds};

    for (final deviceId in allDevices) {
      final ourTime = this[deviceId];
      final theirTime = other[deviceId];

      if (ourTime > theirTime) {
        return false; // We're ahead on this device → not happens-before
      }

      if (ourTime < theirTime) {
        anyLess = true; // We're behind on this device
      }
    }

    return anyLess; // At least one device must be behind
  }

  /// Check if this clock happens after (dominates) another clock.
  ///
  /// A happens-after B if B happens-before A.
  bool happensAfter(VectorClock other) {
    return other.happensBefore(this);
  }

  /// Check if this clock is concurrent (conflicts) with another clock.
  ///
  /// A and B are concurrent if:
  /// - Neither A happens-before B
  /// - NOR B happens-before A
  ///
  /// This indicates a conflict: both changes happened independently.
  bool isConcurrentWith(VectorClock other) {
    return !happensBefore(other) && !other.happensBefore(this);
  }

  /// Compare two vector clocks and return relationship.
  ///
  /// Returns:
  /// - [ClockRelationship.before]: this happens before other
  /// - [ClockRelationship.after]: this happens after other
  /// - [ClockRelationship.concurrent]: conflict (both independent)
  /// - [ClockRelationship.equal]: identical clocks
  ClockRelationship compareTo(VectorClock other) {
    if (_isEqual(other)) return ClockRelationship.equal;
    if (happensBefore(other)) return ClockRelationship.before;
    if (happensAfter(other)) return ClockRelationship.after;
    return ClockRelationship.concurrent;
  }

  /// Check if two vector clocks are equal.
  bool _isEqual(VectorClock other) {
    final allDevices = {...deviceIds, ...other.deviceIds};

    for (final deviceId in allDevices) {
      if (this[deviceId] != other[deviceId]) {
        return false;
      }
    }

    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VectorClock) return false;
    return _isEqual(other);
  }

  @override
  int get hashCode => _clocks.hashCode;

  @override
  String toString() {
    final entries = _clocks.entries
        .map((e) => '${e.key}:${e.value}')
        .join(', ');
    return 'VectorClock{$entries}';
  }

  /// Create a compact string representation (for debugging).
  ///
  /// Example: "A:5,B:3,C:1"
  String toCompactString() {
    final sorted = _clocks.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => '${_shortDeviceId(e.key)}:${e.value}').join(',');
  }

  /// Shorten device ID for display (first 4 chars).
  static String _shortDeviceId(String deviceId) {
    return deviceId.length > 4 ? deviceId.substring(0, 4) : deviceId;
  }
}

/// Relationship between two vector clocks.
enum ClockRelationship {
  /// Clocks are identical
  equal,

  /// This clock happens before the other (this is older)
  before,

  /// This clock happens after the other (this is newer)
  after,

  /// Clocks are concurrent (conflict!)
  concurrent,
}

/// Extension for readable comparison results.
extension ClockRelationshipX on ClockRelationship {
  bool get isConflict => this == ClockRelationship.concurrent;
  bool get isEqual => this == ClockRelationship.equal;
  bool get canMerge =>
      this == ClockRelationship.before ||
      this == ClockRelationship.after ||
      this == ClockRelationship.equal;
}
