import '../../data/models/loan_payment.dart';

/// Abstract interface for loan payment schedule persistence.
abstract class LoanPaymentRepository {
  /// Get all payments for a loan, ordered by installment number.
  Future<List<LoanPayment>> getByLoanId(int loanId);

  /// Get upcoming (unpaid) payments for a loan.
  Future<List<LoanPayment>> getUpcoming(int loanId);

  /// Get overdue (unpaid, past due) payments for a loan.
  Future<List<LoanPayment>> getOverdue(int loanId);

  /// Get the next unpaid payment for a loan.
  Future<LoanPayment?> getNextPayment(int loanId);

  /// Insert a batch of scheduled payments (when generating schedule).
  Future<void> insertAll(List<LoanPayment> payments);

  /// Mark a payment as paid (fully or partially).
  Future<void> markPaid(int paymentId, double amount);

  /// Delete all payments for a loan (when regenerating schedule).
  Future<void> deleteByLoanId(int loanId);

  /// Get count of paid installments for a loan.
  Future<int> getPaidCount(int loanId);

  /// Get total paid amount across all installments for a loan.
  Future<double> getTotalPaid(int loanId);
}
