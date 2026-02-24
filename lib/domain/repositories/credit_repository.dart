import '../../data/models/credit_record.dart';

/// Summary of a customer's credit history.
class CustomerCreditSummary {
  const CustomerCreditSummary({
    required this.customerName,
    this.phoneNumber,
    required this.totalGiven,
    required this.totalReceived,
    required this.totalPending,
    required this.pendingCount,
    required this.clearedCount,
    required this.overdueCount,
  });

  final String customerName;
  final String? phoneNumber;
  final double totalGiven;
  final double totalReceived;
  final double totalPending;
  final int pendingCount;
  final int clearedCount;
  final int overdueCount;
}

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

  /// Record a payment against a credit record and store a CreditPayment.
  Future<void> recordPayment(int creditId, double amount, {
    String? paymentMethod,
    int? transactionId,
    String? notes,
  });

  /// Get all credit records (including cleared).
  Future<List<CreditRecord>> getAll({int? limit, int? offset});

  /// Search credits by customer name.
  Future<List<CreditRecord>> search(String query);

  /// Get all payments for a specific credit record.
  Future<List<CreditPayment>> getPaymentsForCredit(int creditId);

  /// Get distinct customer names with pending credits, sorted by total pending.
  Future<List<CustomerCreditSummary>> getCustomerSummaries();

  /// Get a summary for a single customer.
  Future<CustomerCreditSummary?> getCustomerSummary(String customerName);

  /// Get all credits that are cleared.
  Future<List<CreditRecord>> getCleared();

  /// Get distinct customer names.
  Future<List<String>> getCustomerNames();
}
