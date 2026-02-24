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

  /// Get category-wise income summary for a date range.
  Future<Map<String, double>> getIncomeByCategorySummary(
      DateTime start, DateTime end);

  /// Get category-wise expense summary for a date range.
  Future<Map<String, double>> getExpenseByCategorySummary(
      DateTime start, DateTime end);

  /// Get daily totals for a date range (for trend charts).
  /// Returns a map of date string (yyyy-MM-dd) -> { 'income': X, 'expense': Y }
  Future<List<DailyTotal>> getDailyTotals(DateTime start, DateTime end);

  /// Get monthly totals for the last N months.
  Future<List<MonthlyTotal>> getMonthlyTotals({int months = 6});

  /// Get top parties by transaction amount for a date range.
  Future<List<PartyTotal>> getTopParties(
    DateTime start,
    DateTime end, {
    int limit = 10,
  });

  /// Check if a transaction with this dedupe hash already exists.
  Future<bool> existsByDedupeHash(String hash);

  /// Get recent transactions (for home screen).
  Future<List<Transaction>> getRecent({int limit = 10});
}

/// Daily income/expense totals.
class DailyTotal {
  const DailyTotal({
    required this.date,
    required this.income,
    required this.expense,
  });
  final DateTime date;
  final double income;
  final double expense;
  double get net => income - expense;
}

/// Monthly income/expense totals.
class MonthlyTotal {
  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });
  final int year;
  final int month;
  final double income;
  final double expense;
  double get net => income - expense;
  String get label {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }
}

/// Party with total transaction amount.
class PartyTotal {
  const PartyTotal({
    required this.partyName,
    required this.totalAmount,
    required this.transactionCount,
  });
  final String partyName;
  final double totalAmount;
  final int transactionCount;
}
