import '../../data/models/budget.dart';

/// Repository interface for per-category monthly budgets.
abstract class BudgetRepository {
  /// Returns all active budgets for [year]/[month], with [spentAmount]
  /// computed from the transactions table.
  Future<List<Budget>> getBudgetsForMonth(int year, int month);

  /// Returns a single budget row for [year]/[month]/[category], or null.
  Future<Budget?> getBudget(int year, int month, String category);

  /// Creates or updates the budget for [year]/[month]/[category].
  Future<void> upsert(Budget budget);

  /// Permanently deletes a budget row by [id].
  Future<void> delete(int id);
}
