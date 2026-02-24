import '../../data/models/bill_attachment.dart';

/// Abstract interface for bill attachment data access.
abstract class BillRepository {
  /// Insert a new bill attachment. Returns the inserted ID.
  Future<int> insert(BillAttachment bill);

  /// Get the bill attachment for a transaction (null if none).
  Future<BillAttachment?> getByTransactionId(int transactionId);

  /// Delete a bill attachment by ID.
  Future<void> delete(int id);

  /// Delete a bill attachment by transaction ID.
  Future<void> deleteByTransactionId(int transactionId);

  /// Check if a transaction has a bill attached.
  Future<bool> hasAttachment(int transactionId);
}
