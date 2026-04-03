import 'sync_signaling_messages.dart';

/// Maps frames between cloud wire format and coordinator schema.
///
/// Enforces schema parity so cloud-path frames are structurally identical to
/// frames exchanged over local signaling. The mapper is the single boundary
/// responsible for validating type-field presence and rejecting unknown types
/// before they enter or leave the coordinator processing pipeline.
class CloudSignalingFrameMapper {
  const CloudSignalingFrameMapper();

  /// Validates and normalizes an inbound cloud frame.
  ///
  /// Returns null for frames with a missing, empty, or unrecognized type field.
  /// Drop policy prevents unknown cloud envelope fields from leaking into the
  /// coordinator processing pipeline.
  Map<String, dynamic>? mapInbound(Map<String, dynamic> cloudFrame) {
    final type = cloudFrame['type'];
    if (type is! String || type.isEmpty) return null;
    if (!_isRoutableType(type)) return null;
    return Map<String, dynamic>.from(cloudFrame);
  }

  /// Validates an outbound coordinator frame before sending to the cloud adapter.
  ///
  /// Throws [ArgumentError] if the frame is missing a type field or carries an
  /// unrecognized type. Fail-fast at the send boundary prevents malformed
  /// protocol messages from reaching the cloud wire.
  Map<String, dynamic> mapOutbound(Map<String, dynamic> coordinatorFrame) {
    final type = coordinatorFrame['type'];
    if (type is! String || type.isEmpty) {
      throw ArgumentError.value(
        coordinatorFrame,
        'coordinatorFrame',
        'Frame must have a non-empty string type field',
      );
    }
    if (!_isRoutableType(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'Frame type is not recognized by the coordinator schema: $type',
      );
    }
    return Map<String, dynamic>.from(coordinatorFrame);
  }

  bool _isRoutableType(String type) =>
      SyncSignalingMessages.isControlPlaneType(type) ||
      SyncSignalingMessages.isDataPlaneEligibleType(type);
}
