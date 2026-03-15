import '../models/delta_row.dart';
import '../models/device_session_token.dart';

/// Transport-level abstraction over TCP ([SyncClient]) and WebSocket
/// ([WsSyncTransport]) sync.
///
/// [open] accepts a [Uri] so callers are transport-agnostic:
/// - TCP : `Uri(scheme: 'kashcube-tcp', host: ip, port: port)`
/// - WS  : `Uri.parse('ws://ip:port/ws?token=...')`
abstract class SyncTransport {
  Future<void> open(Uri endpoint);
  Future<void> close();

  Future<DeviceSession> sendPairRequest({
    required String preset,
    required String deviceOs,
    required String deviceType,
    required String deviceName,
    String? secondaryIdentityId,
    String? secondaryDisplayName,
  });

  Future<int> pullDeltas({required DeviceSession session, DateTime? lastSyncAt});
  Future<int> pushDeltas({required DeviceSession session, required List<DeltaRow> rows});
  Future<List<DeltaRow>> buildLocalDeltas({DateTime? since});

  /// Ask the primary to atomically reserve [count] sequential document
  /// numbers of [docType] ('invoice', 'quote', 'dc', 'credit_note',
  /// 'debit_note').  The caller must be connected before calling.
  Future<List<String>> reserveNumber({
    required DeviceSession session,
    required String docType,
    int count = 1,
  });
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => 'SyncException: $message';
}

class SyncRevokedException extends SyncException {
  const SyncRevokedException(super.message);

  @override
  String toString() => 'SyncRevokedException: $message';
}
