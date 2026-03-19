import '../../data/models/business.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/business_repository.dart';

class BusinessRepositoryImpl implements BusinessRepository {
  BusinessRepositoryImpl({DatabaseHelper? dbHelper, this.contextId})
      : _db = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx =>
      contextId == null ? 'context_id IS NULL' : 'context_id = $contextId';

  @override
  Future<List<Business>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'businesses',
      where: _ctx,
    );
    return rows.map(Business.fromMap).toList();
  }

  @override
  Future<Business?> getActive() async {
    final db = await _db.database;
    final rows = await db.query(
      'businesses',
      where: 'is_active = 1 AND $_ctx',
      limit: 1,
    );
    return rows.isEmpty ? null : Business.fromMap(rows.first);
  }

  @override
  Future<Business?> getById(int id) async {
    final db = await _db.database;
    final rows =
        await db.query('businesses', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Business.fromMap(rows.first);
  }

  @override
  Future<int> insert(Business business, {bool setActive = false}) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.transaction((txn) async {
      if (setActive) {
        await txn.update('businesses', {'is_active': 0},
            where: _ctx);
      }
      return txn.insert('businesses', {
        ...business.toMap(),
        'context_id': contextId,
        'is_active': setActive ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      });
    });
    _db.notifyChange('businesses');
    return id;
  }

  @override
  Future<void> update(Business business) async {
    final db = await _db.database;
    await db.update(
      'businesses',
      {
        ...business.toMap(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [business.id],
    );
    _db.notifyChange('businesses');
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('businesses', where: 'id = ?', whereArgs: [id]);
    _db.notifyChange('businesses');
  }

  @override
  Future<void> setActive(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('businesses', {'is_active': 0},
          where: _ctx);
      await txn.update(
        'businesses',
        {'is_active': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _db.notifyChange('businesses');
  }
}
