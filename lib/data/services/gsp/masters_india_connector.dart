// ─────────────────────────────────────────────────────────────────────────────
// THIS FILE IS THE ONLY PLACE IN KashCube THAT WILL MAKE NETWORK CALLS.
//
// It is DISABLED by default. It will only be activated when:
//   1. User explicitly enables "GSP Connect" in Settings.
//   2. User has accepted the data-sharing consent dialog.
//   3. A valid Masters India API key is stored in flutter_secure_storage.
//
// Until all three conditions are met, this class must NOT be instantiated
// and NO network calls occur anywhere in the app.
//
// If you are adding network calls OUTSIDE of this directory, STOP.
// That would violate KashCube's privacy-first architecture.
// ─────────────────────────────────────────────────────────────────────────────

import '../../models/ewb_transport_details.dart';
import '../../models/invoice.dart';
import '../../../domain/repositories/gsp_connector.dart';

/// Stub implementation of [GspConnector] for Masters India GSP.
///
/// TODO (Phase D3): implement using Masters India REST API.
/// Sandbox docs: https://sandbox.mastersindia.co/docs/
/// All methods currently throw [UnimplementedError].
class MastersIndiaConnector implements GspConnector {
  const MastersIndiaConnector({required this.apiKey});

  /// API key stored in flutter_secure_storage (never in SQLite).
  final String apiKey;

  @override
  Future<GspEwbResult> generateEwb(
    Invoice invoice,
    EwbTransportDetails transport,
  ) async {
    // TODO(D3): POST /ewb/generate with GSTN EWB JSON payload.
    throw UnimplementedError(
      'MastersIndiaConnector.generateEwb() not yet implemented. '
      'Phase D3 is required first.',
    );
  }

  @override
  Future<void> cancelEwb(
    String ewbNo,
    int cancelReason, {
    String? cancelRemark,
  }) async {
    // TODO(D3): POST /ewb/cancel
    throw UnimplementedError(
      'MastersIndiaConnector.cancelEwb() not yet implemented.',
    );
  }

  @override
  Future<void> updateVehicle(
    String ewbNo,
    String newVehicleNo, {
    String mode = '1',
    String? reasonCode,
  }) async {
    // TODO(D3): POST /ewb/veh_update
    throw UnimplementedError(
      'MastersIndiaConnector.updateVehicle() not yet implemented.',
    );
  }
}
