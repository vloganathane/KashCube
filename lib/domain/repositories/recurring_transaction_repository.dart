import '../../data/models/recurring_transaction.dart';

/// Abstract interface for recurring transaction data access.
abstract class RecurringTransactionRepository {
  /// Get all recurring transactions.
  Future<List<RecurringTransaction>> getAll();

  /// Get only active recurring transactions.
  Future<List<RecurringTransaction>> getActive();

  /// Get a recurring transaction by ID.
  Future<RecurringTransaction?> getById(int id);

  /// Get recurring transactions that are due (nextDate <= now).
  Future<List<RecurringTransaction>> getDue();

  /// Insert a new recurring transaction. Returns the inserted ID.
  Future<int> insert(RecurringTransaction recurring);

  /// Update an existing recurring transaction.
  Future<void> update(RecurringTransaction recurring);

  /// Delete a recurring transaction by ID.
  Future<void> delete(int id);

  /// Toggle active/inactive status.
  Future<void> toggleActive(int id, bool isActive);
}
