import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/budget_repository.dart';
import '../models/budget.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [BudgetRepository].
///
/// `spentAmount` for each [Budget] is computed on-the-fly from the
/// `transactions` table so it always reflects real data.
class BudgetRepositoryImpl implements BudgetRepository {
  BudgetRepositoryImpl([DatabaseHelper? db])
      : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  static const _table = 'budgets';

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Future<List<Budget>> getBudgetsForMonth(int year, int month) async {
    final db = await _db.database;

    // 1. Load budget rows
    final budgetRows = await db.query(
      _table,
      where: 'year = ? AND month = ? AND is_active = 1',
      whereArgs: [year, month],
      orderBy: 'category ASC',
    );

    if (budgetRows.isEmpty) return const [];

    // 2. Compute actual spend per category from transactions
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 1).toIso8601String();

    final spendRows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense'
        AND deleted_at IS NULL
        AND date >= ? AND date < ?
      GROUP BY category
      ''',
      [start, end],
    );

    final spendByCategory = {
      for (final row in spendRows)
        (row['category'] as String): (row['total'] as num).toDouble(),
    };

    return budgetRows.map((row) {
      final b = Budget.fromMap(row);
      final spent = spendByCategory[b.category] ?? 0.0;
      return b.copyWith(spentAmount: spent);
    }).toList();
  }

  @override
  Future<Budget?> getBudget(int year, int month, String category) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'year = ? AND month = ? AND category = ?',
      whereArgs: [year, month, category],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final b = Budget.fromMap(rows.first);
    // Compute spent for this single budget
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 1).toIso8601String();
    final spendRows = await db.rawQuery(
      '''
      SELECT SUM(amount) AS total FROM transactions
      WHERE type = 'expense' AND deleted_at IS NULL
        AND date >= ? AND date < ? AND category = ?
      ''',
      [start, end, category],
    );
    final spent =
        (spendRows.first['total'] as num? ?? 0).toDouble();
    return b.copyWith(spentAmount: spent);
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  @override
  Future<void> upsert(Budget budget) async {
    final db = await _db.database;
    try {
      await db.insert(
        _table,
        budget.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('BudgetRepo.upsert error: $e');
      rethrow;
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
