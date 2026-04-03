import 'sync_transport_channel.dart';

/// Placeholder channel for future cloud signaling.
///
/// This intentionally fails closed in the local-first build so cloud signaling
/// can be feature-flagged and exercised without introducing network behavior.
class CloudSignalingUnavailableTransportChannel implements SyncTransportChannel {
  static const unsupportedReason =
      'Cloud signaling is not available in this local-first build';

  @override
  Future<void> connect(Uri uri) async {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Stream<dynamic> get stream => const Stream<dynamic>.empty();

  @override
  void sendJson(Map<String, dynamic> payload) {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<void> close() async {}
}
