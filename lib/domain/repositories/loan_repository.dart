import '../../data/models/loan.dart';

/// Summary of ledger entries for a single party.
class PartyLedgerSummary {
  final String partyName;
  final double totalLent;
  final double totalBorrowed;
  final double pendingLent;
  final double pendingBorrowed;
  final int activeCount;

  const PartyLedgerSummary({
    required this.partyName,
    this.totalLent = 0,
    this.totalBorrowed = 0,
    this.pendingLent = 0,
    this.pendingBorrowed = 0,
    this.activeCount = 0,
  });
}

/// Abstract interface for loan persistence.
abstract class LoanRepository {
  /// Get all active (non-deleted) loans.
  Future<List<Loan>> getAll();

  /// Get active (not cleared, not deleted) loans.
  Future<List<Loan>> getActive();

  /// Get active loans filtered by direction.
  Future<List<Loan>> getActiveByDirection(LoanDirection direction);

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

  /// Get total pending amount for lent entries.
  Future<double> getTotalPendingLent();

  /// Get total pending amount for borrowed entries.
  Future<double> getTotalPendingBorrowed();

  /// Get party-wise summaries for the customer grouping view.
  Future<List<PartyLedgerSummary>> getPartySummaries();

  /// Get all loans for a specific party name.
  Future<List<Loan>> getByPartyName(String partyName);

  /// Get distinct party names for autocomplete.
  Future<List<String>> getPartyNames();
}
