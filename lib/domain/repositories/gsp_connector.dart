import '../../data/models/ewb_transport_details.dart';
import '../../data/models/invoice.dart';

/// Result returned by a GSP connector after successfully generating an EWB.
class GspEwbResult {
  const GspEwbResult({
    required this.ewbNo,
    required this.generatedAt,
    required this.validUntil,
  });

  /// EWB number assigned by GSTN (12-digit, e.g. '331012345678').
  final String ewbNo;

  /// Timestamp when GSTN assigned the EWB.
  final DateTime generatedAt;

  /// Validity expiry date computed by GSTN.
  final DateTime validUntil;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Abstract interface for GSP (GST Suvidha Provider) connectivity.
///
/// All network-calling code in KashCube lives in implementations of this
/// interface. The interface itself contains zero network calls.
///
/// IMPORTANT: Implementations must ONLY be instantiated when:
///   1. The user has explicitly enabled GSP in Settings.
///   2. The user has given written consent (gsp_consent_given_at is set).
///   3. A valid API key is stored in flutter_secure_storage.
///
/// Default state: GSP is DISABLED. [EwayBillService.exportAndShare] uses
/// local JSON export (Option A) unless a GspConnector is injected.
/// ─────────────────────────────────────────────────────────────────────────────
abstract class GspConnector {
  /// Generates an e-Way Bill for [invoice] with [transport] details.
  ///
  /// Returns [GspEwbResult] on success. Throws [GspException] on failure.
  Future<GspEwbResult> generateEwb(
    Invoice invoice,
    EwbTransportDetails transport,
  );

  /// Cancels an existing EWB by [ewbNo].
  ///
  /// [cancelReason]: 1=Duplicate, 2=Order Cancelled, 3=Data Entry Mistake,
  ///                 4=Others.
  Future<void> cancelEwb(
    String ewbNo,
    int cancelReason, {
    String? cancelRemark,
  });

  /// Updates the vehicle number for an existing EWB (Part B update).
  Future<void> updateVehicle(
    String ewbNo,
    String newVehicleNo, {
    String mode = '1',
    String? reasonCode,
  });
}

/// Exception thrown by GSP connector implementations.
class GspException implements Exception {
  const GspException(this.message, {this.code});

  /// Human-readable error message from the GSP.
  final String message;

  /// Optional GSP/GSTN error code (e.g. '4001', '4002').
  final String? code;

  @override
  String toString() => code != null
      ? 'GspException [$code]: $message'
      : 'GspException: $message';
}
