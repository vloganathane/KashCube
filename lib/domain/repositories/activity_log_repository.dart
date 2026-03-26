import '../../data/models/activity_log.dart';

/// Generic activity log repository — usable for any entity type.
/// Entity types are plain strings (e.g. 'quote', 'invoice', 'credit').
abstract class ActivityLogRepository {
  /// Append a new log entry. Returns the inserted row id.
  Future<int> log(ActivityLog entry);

  /// Fetch all entries for a given entity, newest first.
  Future<List<ActivityLog>> getForEntity(String entityType, int entityId);

  /// Delete all log entries for a given entity (e.g. when the entity is deleted).
  Future<void> deleteForEntity(String entityType, int entityId);
}
