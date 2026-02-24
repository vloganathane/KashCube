import '../../data/models/transaction.dart';

/// Abstract interface for transaction data access.
abstract class TransactionRepository {
  /// Insert a new transaction. Returns the inserted ID.
  Future<int> insert(Transaction transaction);

  /// Update an existing transaction.
  Future<void> update(Transaction transaction);

  /// Soft-delete a transaction by ID.
  Future<void> delete(int id);

  /// Get a single transaction by ID.
  Future<Transaction?> getById(int id);

  /// Get all non-deleted transactions, ordered by date descending.
  Future<List<Transaction>> getAll({int? limit, int? offset});

  /// Get transactions filtered by date range.
  Future<List<Transaction>> getByDateRange(DateTime start, DateTime end);

  /// Get transactions by category.
  Future<List<Transaction>> getByCategory(String category, {int? limit});

  /// Get transactions by type (income/expense).
  Future<List<Transaction>> getByType(TransactionType type, {int? limit});

  /// Search transactions by party name or notes.
  Future<List<Transaction>> search(String query);

  /// Get total income for a date range.
  Future<double> getTotalIncome(DateTime start, DateTime end);

  /// Get total expense for a date range.
  Future<double> getTotalExpense(DateTime start, DateTime end);

  /// Get category-wise spending summary for a date range.
  Future<Map<String, double>> getCategorySummary(DateTime start, DateTime end);

  /// Check if a transaction with this dedupe hash already exists.
  Future<bool> existsByDedupeHash(String hash);

  /// Get recent transactions (for home screen).
  Future<List<Transaction>> getRecent({int limit = 10});
}
