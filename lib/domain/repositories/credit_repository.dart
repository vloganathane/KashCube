import '../../data/models/credit_record.dart';

/// Abstract interface for credit record data access.
abstract class CreditRepository {
  /// Insert a new credit record. Returns the inserted ID.
  Future<int> insert(CreditRecord credit);

  /// Update an existing credit record.
  Future<void> update(CreditRecord credit);

  /// Soft-delete a credit record by ID.
  Future<void> delete(int id);

  /// Get a single credit record by ID.
  Future<CreditRecord?> getById(int id);

  /// Get all pending (non-cleared, non-deleted) credit records.
  Future<List<CreditRecord>> getPending();

  /// Get all overdue credit records.
  Future<List<CreditRecord>> getOverdue();

  /// Get credit records for a specific customer.
  Future<List<CreditRecord>> getByCustomer(String customerName);

  /// Get total pending credit amount.
  Future<double> getTotalPending();

  /// Get total overdue credit amount.
  Future<double> getTotalOverdue();

  /// Record a payment against a credit record.
  Future<void> recordPayment(int creditId, double amount);

  /// Get all credit records (including cleared).
  Future<List<CreditRecord>> getAll({int? limit, int? offset});

  /// Search credits by customer name.
  Future<List<CreditRecord>> search(String query);
}
