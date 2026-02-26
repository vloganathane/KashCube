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

  Future<double> getTotalInvested(DateTime start, DateTime end) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type = 'invested' "
      "AND date >= ? AND date <= ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<double> getTotalRedeemed(DateTime start, DateTime end) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type = 'redeemed' "
      "AND date >= ? AND date <= ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<double> getTotalIncome(DateTime start, DateTime end, {String? mode}) async {
    final db = await _db;
    final modeClause = mode != null ? "AND mode = ? " : "";
    final args = <dynamic>[start.toIso8601String(), end.toIso8601String()];
    if (mode != null) args.add(mode);
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM transactions "
      "WHERE deleted_at IS NULL AND type IN ('income', 'received_back', 'redeemed') "
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
      "WHERE deleted_at IS NULL AND type IN ('expense', 'paid_back') "
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
      "WHERE deleted_at IS NULL AND type IN ('income', 'received_back', 'redeemed') "
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
      "WHERE deleted_at IS NULL AND type IN ('expense', 'paid_back') "
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
      "SUM(CASE WHEN type IN ('income', 'received_back', 'redeemed') THEN amount ELSE 0 END) as income, "
      "SUM(CASE WHEN type IN ('expense', 'paid_back') THEN amount ELSE 0 END) as expense "
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
      "SUM(CASE WHEN type IN ('income', 'received_back', 'redeemed') THEN amount ELSE 0 END) as income, "
      "SUM(CASE WHEN type IN ('expense', 'paid_back') THEN amount ELSE 0 END) as expense "
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

  @override
  Future<List<LedgerPartyEntry>> getPartyLedgerSummaries() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT t.party_name, "
      "COALESCE(p.party_type, 'person') as party_type, "
      "SUM(CASE WHEN t.type = 'lent'          THEN t.amount ELSE 0 END) as total_lent, "
      "SUM(CASE WHEN t.type = 'borrowed'       THEN t.amount ELSE 0 END) as total_borrowed, "
      "SUM(CASE WHEN t.type = 'received_back'  THEN t.amount ELSE 0 END) as total_received_back, "
      "SUM(CASE WHEN t.type = 'paid_back'      THEN t.amount ELSE 0 END) as total_paid_back, "
      "SUM(CASE WHEN t.type = 'invested'       THEN t.amount ELSE 0 END) as total_invested, "
      "SUM(CASE WHEN t.type = 'redeemed'       THEN t.amount ELSE 0 END) as total_redeemed, "
      "SUM(CASE WHEN t.type = 'income'         THEN t.amount ELSE 0 END) as total_income, "
      "SUM(CASE WHEN t.type = 'expense'        THEN t.amount ELSE 0 END) as total_expense, "
      "COUNT(*) as cnt, MAX(t.date) as last_date, "
      "SUM(CASE WHEN t.mode = 'personal' THEN 1 ELSE 0 END) as personal_cnt, "
      "SUM(CASE WHEN t.mode = 'business' THEN 1 ELSE 0 END) as business_cnt "
      "FROM transactions t "
      "LEFT JOIN parties p ON LOWER(TRIM(p.name)) = LOWER(TRIM(t.party_name)) "
      "WHERE t.deleted_at IS NULL AND t.party_name IS NOT NULL AND t.party_name != '' "
      "AND t.type != 'transfer' "
      "GROUP BY LOWER(TRIM(t.party_name)) "
      "ORDER BY MAX(t.date) DESC",
    );
    return rows.map((r) => LedgerPartyEntry(
      partyName: r['party_name'] as String,
      partyType: r['party_type'] as String? ?? 'person',
      totalLent:          (r['total_lent']          as num).toDouble(),
      totalBorrowed:      (r['total_borrowed']       as num).toDouble(),
      totalReceivedBack:  (r['total_received_back']  as num).toDouble(),
      totalPaidBack:      (r['total_paid_back']      as num).toDouble(),
      totalInvested:      (r['total_invested']       as num).toDouble(),
      totalRedeemed:      (r['total_redeemed']       as num).toDouble(),
      totalIncome:        (r['total_income']          as num).toDouble(),
      totalExpense:       (r['total_expense']         as num).toDouble(),
      transactionCount:   (r['cnt'] as num).toInt(),
      personalCount:      (r['personal_cnt'] as num).toInt(),
      businessCount:      (r['business_cnt'] as num).toInt(),
      lastTransactionDate: r['last_date'] != null
          ? DateTime.tryParse(r['last_date'] as String)
          : null,
    )).toList();
  }

  @override
  Future<List<Transaction>> getTransactionsByParty(String partyName) async {
    final db = await _db;
    // Return ALL transaction types for this party (full khata view).
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL AND LOWER(TRIM(party_name)) = LOWER(TRIM(?))',
      whereArgs: [partyName],
      orderBy: 'date ASC',  // ascending for running-balance chronology
    );
    return rows.map((r) => Transaction.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  @override
  Future<double> getTotalOutstandingLent() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT "
      "COALESCE(SUM(CASE WHEN type = 'lent' THEN amount ELSE 0 END), 0) - "
      "COALESCE(SUM(CASE WHEN type = 'received_back' THEN amount ELSE 0 END), 0) as net "
      "FROM transactions WHERE deleted_at IS NULL",
    );
    return (rows.first['net'] as num).toDouble();
  }

  @override
  Future<double> getTotalOutstandingBorrowed() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT "
      "COALESCE(SUM(CASE WHEN type = 'borrowed' THEN amount ELSE 0 END), 0) - "
      "COALESCE(SUM(CASE WHEN type = 'paid_back' THEN amount ELSE 0 END), 0) as net "
      "FROM transactions WHERE deleted_at IS NULL",
    );
    return (rows.first['net'] as num).toDouble();
  }
}
