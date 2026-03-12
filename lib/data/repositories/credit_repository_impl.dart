import 'package:sqflite/sqflite.dart';

import '../models/credit.dart';
import '../services/database_helper.dart';
import '../../domain/repositories/credit_repository.dart';

class CreditRepositoryImpl implements CreditRepository {
  CreditRepositoryImpl([DatabaseHelper? helper, this.contextId])
      : _db = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx =>
      contextId == null ? 'context_id IS NULL' : 'context_id = $contextId';

  static const _table = 'credits';

  // ── Queries ───────────────────────────────────────────────────────────────

  @override
  Future<List<Credit>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'deleted_at IS NULL AND $_ctx',
      orderBy: 'credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  @override
  Future<List<Credit>> getActive() async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'is_cleared = 0 AND deleted_at IS NULL AND $_ctx',
      orderBy: 'credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  @override
  Future<List<Credit>> getPersonal() async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'business_id IS NULL AND is_cleared = 0 AND deleted_at IS NULL AND $_ctx',
      orderBy: 'credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  @override
  Future<List<Credit>> getForBusiness(int businessId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'business_id = ? AND is_cleared = 0 AND deleted_at IS NULL AND $_ctx',
      whereArgs: [businessId],
      orderBy: 'credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  @override
  Future<List<Credit>> getByPartyName(String partyName) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'customer_name = ? AND deleted_at IS NULL AND $_ctx',
      whereArgs: [partyName],
      orderBy: 'credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  @override
  Future<List<Credit>> getActiveByDirection(CreditDirection direction) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where:
          'direction = ? AND is_cleared = 0 AND deleted_at IS NULL AND $_ctx',
      whereArgs: [direction.dbValue],
      orderBy: 'credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  @override
  Future<List<Credit>> getOverdue() async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where:
          'is_cleared = 0 AND deleted_at IS NULL AND $_ctx AND due_date < ? AND due_date IS NOT NULL',
      whereArgs: [DateTime.now().toIso8601String()],
      orderBy: 'due_date ASC',
    );
    return rows.map(Credit.fromMap).toList();
  }

  // ── Aggregates ────────────────────────────────────────────────────────────

  @override
  Future<double> getTotalPendingGiven() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) AS total FROM $_table "
      "WHERE direction = 'given' AND is_cleared = 0 AND deleted_at IS NULL AND $_ctx",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<double> getTotalPendingReceived() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) AS total FROM $_table "
      "WHERE direction = 'received' AND is_cleared = 0 AND deleted_at IS NULL AND $_ctx",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<double> getPersonalTotalPendingGiven() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) AS total FROM $_table "
      "WHERE direction = 'given' AND business_id IS NULL "
      "AND is_cleared = 0 AND deleted_at IS NULL AND $_ctx",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<List<PartyCreditSummary>> getPartySummaries() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        customer_name,
        SUM(CASE WHEN direction = 'given'    THEN total_amount   ELSE 0 END) AS total_given,
        SUM(CASE WHEN direction = 'received' THEN total_amount   ELSE 0 END) AS total_received,
        SUM(CASE WHEN direction = 'given'    THEN pending_amount ELSE 0 END) AS pending_given,
        SUM(CASE WHEN direction = 'received' THEN pending_amount ELSE 0 END) AS pending_received,
        COUNT(*) AS active_count
      FROM $_table
      WHERE is_cleared = 0 AND deleted_at IS NULL AND $_ctx
      GROUP BY customer_name
      ORDER BY pending_given DESC
    ''');
    return rows.map((r) => PartyCreditSummary(
          partyName: r['customer_name'] as String,
          totalGiven: (r['total_given'] as num?)?.toDouble() ?? 0,
          totalReceived: (r['total_received'] as num?)?.toDouble() ?? 0,
          pendingGiven: (r['pending_given'] as num?)?.toDouble() ?? 0,
          pendingReceived: (r['pending_received'] as num?)?.toDouble() ?? 0,
          activeCount: (r['active_count'] as int?) ?? 0,
        )).toList();
  }

  @override
  Future<List<String>> getPartyNames() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT customer_name FROM $_table WHERE deleted_at IS NULL AND $_ctx ORDER BY customer_name',
    );
    return rows.map((r) => r['customer_name'] as String).toList();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  @override
  Future<int> insert(Credit credit) async {
    final db = await _db.database;
    final map = credit.toMap();
    map['context_id'] = contextId;
    return db.insert(_table, map);
  }

  @override
  Future<void> update(Credit credit) async {
    final db = await _db.database;
    await db.update(
      _table,
      credit.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [credit.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.update(
      _table,
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> recordPayment(int creditId, double amount) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['total_amount', 'paid_amount', 'pending_amount'],
        where: 'id = ?',
        whereArgs: [creditId],
      );
      if (rows.isEmpty) return;
      final totalAmount = (rows.first['total_amount'] as num).toDouble();
      final paidAmount =
          (rows.first['paid_amount'] as num?)?.toDouble() ?? 0;
      final newPaid = (paidAmount + amount).clamp(0, totalAmount);
      final newPending = totalAmount - newPaid;
      final isCleared = newPending <= 0.001 ? 1 : 0;
      await txn.update(
        _table,
        {
          'paid_amount': newPaid,
          'pending_amount': newPending,
          'is_cleared': isCleared,
          'cleared_date': isCleared == 1
              ? DateTime.now().toIso8601String()
              : null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [creditId],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<Credit>> getByCustomerId(int partyId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'customer_id = ? AND deleted_at IS NULL AND $_ctx',
      whereArgs: [partyId],
      orderBy: 'is_cleared ASC, credit_date DESC',
    );
    return rows.map(Credit.fromMap).toList();
  }
}
