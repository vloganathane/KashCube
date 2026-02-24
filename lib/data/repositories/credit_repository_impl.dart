import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../domain/repositories/credit_repository.dart';
import '../models/credit_record.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [CreditRepository].
class CreditRepositoryImpl implements CreditRepository {
  final DatabaseHelper _dbHelper;

  CreditRepositoryImpl({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<int> insert(CreditRecord credit) async {
    final db = await _db;
    return db.insert('credits', credit.toMap());
  }

  @override
  Future<void> update(CreditRecord credit) async {
    final db = await _db;
    final map = credit.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      'credits',
      map,
      where: 'id = ?',
      whereArgs: [credit.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.update(
      'credits',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<CreditRecord?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'credits',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CreditRecord.fromMap(rows.first);
  }

  @override
  Future<List<CreditRecord>> getPending() async {
    final db = await _db;
    final rows = await db.query(
      'credits',
      where: 'deleted_at IS NULL AND is_cleared = 0',
      orderBy: 'due_date ASC, pending_amount DESC',
    );
    return rows.map((r) => CreditRecord.fromMap(r)).toList();
  }

  @override
  Future<List<CreditRecord>> getOverdue() async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'credits',
      where: 'deleted_at IS NULL AND is_cleared = 0 AND due_date IS NOT NULL AND due_date < ?',
      whereArgs: [now],
      orderBy: 'due_date ASC',
    );
    return rows.map((r) => CreditRecord.fromMap(r)).toList();
  }

  @override
  Future<List<CreditRecord>> getByCustomer(String customerName) async {
    final db = await _db;
    final rows = await db.query(
      'credits',
      where: 'deleted_at IS NULL AND customer_name = ?',
      whereArgs: [customerName],
      orderBy: 'credit_date DESC',
    );
    return rows.map((r) => CreditRecord.fromMap(r)).toList();
  }

  @override
  Future<double> getTotalPending() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) as total FROM credits "
      "WHERE deleted_at IS NULL AND is_cleared = 0",
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<double> getTotalOverdue() async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) as total FROM credits "
      "WHERE deleted_at IS NULL AND is_cleared = 0 AND due_date IS NOT NULL AND due_date < ?",
      [now],
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<void> recordPayment(int creditId, double amount) async {
    final db = await _db;
    final credit = await getById(creditId);
    if (credit == null) return;

    final newPaid = credit.paidAmount + amount;
    final newPending = credit.totalAmount - newPaid;
    final isCleared = newPending <= 0;

    await db.update(
      'credits',
      {
        'paid_amount': newPaid,
        'pending_amount': newPending.clamp(0, double.infinity),
        'is_cleared': isCleared ? 1 : 0,
        'cleared_date': isCleared ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [creditId],
    );
  }

  @override
  Future<List<CreditRecord>> getAll({int? limit, int? offset}) async {
    final db = await _db;
    final rows = await db.query(
      'credits',
      where: 'deleted_at IS NULL',
      orderBy: 'credit_date DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => CreditRecord.fromMap(r)).toList();
  }

  @override
  Future<List<CreditRecord>> search(String query) async {
    final db = await _db;
    final pattern = '%$query%';
    final rows = await db.query(
      'credits',
      where: 'deleted_at IS NULL AND (customer_name LIKE ? OR notes LIKE ?)',
      whereArgs: [pattern, pattern],
      orderBy: 'credit_date DESC',
      limit: 50,
    );
    return rows.map((r) => CreditRecord.fromMap(r)).toList();
  }
}
