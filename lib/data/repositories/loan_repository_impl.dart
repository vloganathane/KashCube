import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/loan_repository.dart';
import '../models/loan.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [LoanRepository].
class LoanRepositoryImpl implements LoanRepository {
  final DatabaseHelper _dbHelper;

  LoanRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<List<Loan>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL',
      orderBy: 'loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getActive() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL AND is_cleared = 0',
      orderBy: 'due_date ASC, loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getCleared() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL AND is_cleared = 1',
      orderBy: 'cleared_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getOverdue() async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'loans',
      where:
          'deleted_at IS NULL AND is_cleared = 0 AND due_date IS NOT NULL AND due_date < ?',
      whereArgs: [now],
      orderBy: 'due_date ASC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<Loan?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Loan.fromMap(rows.first);
  }

  @override
  Future<int> insert(Loan loan) async {
    final db = await _db;
    return db.insert('loans', loan.toMap());
  }

  @override
  Future<void> update(Loan loan) async {
    final db = await _db;
    final map = loan.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update('loans', map, where: 'id = ?', whereArgs: [loan.id]);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.update(
      'loans',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> recordPayment(int loanId, double amount) async {
    final db = await _db;
    final loan = await getById(loanId);
    if (loan == null) return;

    final newPaid = loan.paidAmount + amount;
    final newPending = (loan.principalAmount - newPaid).clamp(0, double.infinity);
    final isCleared = newPending <= 0;

    await db.update(
      'loans',
      {
        'paid_amount': newPaid,
        'pending_amount': newPending,
        'is_cleared': isCleared ? 1 : 0,
        if (isCleared) 'cleared_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [loanId],
    );
  }

  @override
  Future<double> getTotalPending() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(pending_amount), 0) as total '
      'FROM loans WHERE deleted_at IS NULL AND is_cleared = 0',
    );
    return (result.first['total'] as num).toDouble();
  }
}
