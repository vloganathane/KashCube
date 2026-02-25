import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../domain/repositories/transaction_repository.dart';
import '../models/transaction.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [TransactionRepository].
class TransactionRepositoryImpl implements TransactionRepository {
  final DatabaseHelper _dbHelper;

  TransactionRepositoryImpl({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<int> insert(Transaction transaction) async {
    final db = await _db;
    return db.insert('transactions', transaction.toMap());
  }

  @override
  Future<void> update(Transaction transaction) async {
    final db = await _db;
    final map = transaction.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      'transactions',
      map,
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.update(
      'transactions',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Transaction?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Transaction.fromMap(rows.first);
  }

  @override
  Future<List<Transaction>> getAll({int? limit, int? offset}) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL',
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  @override
  Future<List<Transaction>> getByDateRange(DateTime start, DateTime end) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL AND date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  @override
  Future<List<Transaction>> getByCategory(String category, {int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL AND category = ?',
      whereArgs: [category],
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  @override
  Future<List<Transaction>> getByType(TransactionType type, {int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL AND type = ?',
      whereArgs: [type.dbValue],
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  @override
  Future<List<Transaction>> search(String query) async {
    final db = await _db;
    final pattern = '%$query%';
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL AND (party_name LIKE ? OR notes LIKE ? OR category LIKE ?)',
      whereArgs: [pattern, pattern, pattern],
      orderBy: 'date DESC',
      limit: 50,
    );
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  @override
  Future<double> getTotalIncome(DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type IN ('income', 'credit_received', 'loan_taken') "
      "AND date >= ? AND date <= ? $modeClause",
      args,
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<double> getTotalExpense(DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type IN ('expense', 'credit_given', 'loan_repayment') "
      "AND date >= ? AND date <= ? $modeClause",
      args,
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<Map<String, double>> getCategorySummary(DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM transactions "
      "WHERE deleted_at IS NULL AND date >= ? AND date <= ? $modeClause"
      "GROUP BY category ORDER BY total DESC",
      args,
    );
    return {for (final r in rows) r['category'] as String: (r['total'] as num).toDouble()};
  }

  @override
  Future<Map<String, double>> getIncomeByCategorySummary(
      DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type IN ('income', 'credit_received', 'loan_taken') "
      "AND date >= ? AND date <= ? $modeClause"
      "GROUP BY category ORDER BY total DESC",
      args,
    );
    return {for (final r in rows) r['category'] as String: (r['total'] as num).toDouble()};
  }

  @override
  Future<Map<String, double>> getExpenseByCategorySummary(
      DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type IN ('expense', 'credit_given', 'loan_repayment') "
      "AND date >= ? AND date <= ? $modeClause"
      "GROUP BY category ORDER BY total DESC",
      args,
    );
    return {for (final r in rows) r['category'] as String: (r['total'] as num).toDouble()};
  }

  @override
  Future<List<DailyTotal>> getDailyTotals(DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final rows = await db.rawQuery(
      "SELECT date(date) as day, "
      "SUM(CASE WHEN type IN ('income', 'credit_received', 'loan_taken') THEN amount ELSE 0 END) as income, "
      "SUM(CASE WHEN type IN ('expense', 'credit_given', 'loan_repayment') THEN amount ELSE 0 END) as expense "
      "FROM transactions "
      "WHERE deleted_at IS NULL AND date >= ? AND date <= ? $modeClause"
      "GROUP BY day ORDER BY day",
      args,
    );
    return rows
        .map((r) => DailyTotal(
              date: DateTime.parse(r['day'] as String),
              income: (r['income'] as num).toDouble(),
              expense: (r['expense'] as num).toDouble(),
            ))
        .toList();
  }

  @override
  Future<List<MonthlyTotal>> getMonthlyTotals({int months = 6, String? mode}) async {
    final db = await _db;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - months + 1, 1);
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String()];
    if (mode != null) args.add(mode);
    final rows = await db.rawQuery(
      "SELECT "
      "CAST(strftime('%Y', date) AS INTEGER) as yr, "
      "CAST(strftime('%m', date) AS INTEGER) as mo, "
      "SUM(CASE WHEN type IN ('income', 'credit_received', 'loan_taken') THEN amount ELSE 0 END) as income, "
      "SUM(CASE WHEN type IN ('expense', 'credit_given', 'loan_repayment') THEN amount ELSE 0 END) as expense "
      "FROM transactions "
      "WHERE deleted_at IS NULL AND date >= ? $modeClause"
      "GROUP BY yr, mo ORDER BY yr, mo",
      args,
    );
    return rows
        .map((r) => MonthlyTotal(
              year: (r['yr'] as num).toInt(),
              month: (r['mo'] as num).toInt(),
              income: (r['income'] as num).toDouble(),
              expense: (r['expense'] as num).toDouble(),
            ))
        .toList();
  }

  @override
  Future<List<PartyTotal>> getTopParties(
    DateTime start,
    DateTime end, {
    int limit = 10,
    String? mode,
  }) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    args.add(limit);
    final rows = await db.rawQuery(
      "SELECT party_name, SUM(amount) as total, COUNT(*) as cnt "
      "FROM transactions "
      "WHERE deleted_at IS NULL AND party_name IS NOT NULL AND party_name != '' "
      "AND date >= ? AND date <= ? $modeClause"
      "GROUP BY party_name ORDER BY total DESC LIMIT ?",
      args,
    );
    return rows
        .map((r) => PartyTotal(
              partyName: r['party_name'] as String,
              totalAmount: (r['total'] as num).toDouble(),
              transactionCount: (r['cnt'] as num).toInt(),
            ))
        .toList();
  }

  @override
  Future<bool> existsByDedupeHash(String hash) async {
    final db = await _db;
    final result = await db.query(
      'transactions',
      where: 'dedupe_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  @override
  Future<List<Transaction>> getRecent({int limit = 10}) async {
    return getAll(limit: limit);
  }
}
