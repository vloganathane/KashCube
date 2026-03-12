import '../../data/models/linked_device.dart';

/// Abstract interface for [LinkedDevice] data access.
/// Lives on PRIMARY device only.  The secondary has no linked_devices rows.
abstract class LinkedDeviceRepository {
  /// All registered secondary devices (including revoked).
  Future<List<LinkedDevice>> getAll();

  /// Only non-revoked devices.
  Future<List<LinkedDevice>> getActive();

  /// Look up by [deviceId] (the secondary's own UUID).
  Future<LinkedDevice?> getByDeviceId(String deviceId);

  /// Insert a newly paired device.
  Future<void> insert(LinkedDevice device);

  /// Update an existing device record (e.g. after token refresh).
  Future<void> update(LinkedDevice device);

  /// Revoke a device — sets [revokedAt] to now.
  Future<void> revoke(String deviceId);

  /// Stamp the last successful sync time.
  Future<void> updateLastSync(String deviceId, DateTime syncedAt);
}
