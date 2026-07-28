import '../../data/models/activity_log.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/activity_log_repository.dart';

class ActivityLogRepositoryImpl implements ActivityLogRepository {
  final _db = DatabaseHelper.instance;

  @override
  Future<int> log(ActivityLog entry) async {
    final db = await _db.database;
    final id = await db.insert('activity_log', entry.toMap());
    _db.notifyChange('activity_log');
    return id;
  }

  @override
  Future<List<ActivityLog>> getForEntity(
    String entityType,
    int entityId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      'activity_log',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ActivityLog.fromMap).toList();
  }

  @override
  Future<void> deleteForEntity(String entityType, int entityId) async {
    final db = await _db.database;
    await db.delete(
      'activity_log',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
    _db.notifyChange('activity_log');
  }
}
