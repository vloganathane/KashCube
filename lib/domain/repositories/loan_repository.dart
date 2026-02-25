import '../../data/models/loan.dart';

/// Abstract interface for loan persistence.
abstract class LoanRepository {
  /// Get all active (non-deleted) loans.
  Future<List<Loan>> getAll();

  /// Get active (not cleared, not deleted) loans.
  Future<List<Loan>> getActive();

  /// Get cleared loans.
  Future<List<Loan>> getCleared();

  /// Get overdue loans.
  Future<List<Loan>> getOverdue();

  /// Get a single loan by ID.
  Future<Loan?> getById(int id);

  /// Insert a new loan. Returns the row ID.
  Future<int> insert(Loan loan);

  /// Update an existing loan.
  Future<void> update(Loan loan);

  /// Soft-delete a loan.
  Future<void> delete(int id);

  /// Record a payment against a loan.
  Future<void> recordPayment(int loanId, double amount);

  /// Update loan totals after a schedule installment is directly paid.
  /// Unlike [recordPayment], this does NOT auto-mark installments.
  Future<void> addPaymentAmount(int loanId, double amount);

  /// Get total pending loan amount.
  Future<double> getTotalPending();
}
