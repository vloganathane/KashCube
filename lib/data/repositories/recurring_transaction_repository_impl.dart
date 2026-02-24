import '../../domain/repositories/recurring_transaction_repository.dart';
import '../models/recurring_transaction.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [RecurringTransactionRepository].
class RecurringTransactionRepositoryImpl
    implements RecurringTransactionRepository {
  RecurringTransactionRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;
  static const _table = 'recurring_transactions';

  @override
  Future<List<RecurringTransaction>> getAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, orderBy: 'next_date ASC');
    return rows.map(RecurringTransaction.fromMap).toList();
  }

  @override
  Future<List<RecurringTransaction>> getActive() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'next_date ASC',
    );
    return rows.map(RecurringTransaction.fromMap).toList();
  }

  @override
  Future<RecurringTransaction?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RecurringTransaction.fromMap(rows.first);
  }

  @override
  Future<List<RecurringTransaction>> getDue() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      _table,
      where: 'is_active = ? AND next_date <= ?',
      whereArgs: [1, now],
      orderBy: 'next_date ASC',
    );
    return rows.map(RecurringTransaction.fromMap).toList();
  }

  @override
  Future<int> insert(RecurringTransaction recurring) async {
    final db = await _dbHelper.database;
    return db.insert(_table, recurring.toMap());
  }

  @override
  Future<void> update(RecurringTransaction recurring) async {
    final db = await _dbHelper.database;
    final map = recurring.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      _table,
      map,
      where: 'id = ?',
      whereArgs: [recurring.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> toggleActive(int id, bool isActive) async {
    final db = await _dbHelper.database;
    await db.update(
      _table,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
