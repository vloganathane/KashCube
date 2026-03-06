import '../../data/models/credit.dart';

/// Summary of credit entries for a single party.
class PartyCreditSummary {
  final String partyName;
  final double totalGiven;
  final double totalReceived;
  final double pendingGiven;
  final double pendingReceived;
  final int activeCount;

  const PartyCreditSummary({
    required this.partyName,
    this.totalGiven = 0,
    this.totalReceived = 0,
    this.pendingGiven = 0,
    this.pendingReceived = 0,
    this.activeCount = 0,
  });

  /// Net amount owed TO you (positive means others owe you).
  double get netPending => pendingGiven - pendingReceived;
}

/// Abstract interface for credit (udhar/khata) persistence.
abstract class CreditRepository {
  /// All non-deleted credits.
  Future<List<Credit>> getAll();

  /// Active (not cleared, not deleted) credits.
  Future<List<Credit>> getActive();

  /// Personal credits only (business_id IS NULL).
  Future<List<Credit>> getPersonal();

  /// Credits belonging to a specific business.
  Future<List<Credit>> getForBusiness(int businessId);

  /// Active credits for a specific party name.
  Future<List<Credit>> getByPartyName(String partyName);

  /// Active credits filtered by direction.
  Future<List<Credit>> getActiveByDirection(CreditDirection direction);

  /// Overdue credits (not cleared, past due_date).
  Future<List<Credit>> getOverdue();

  /// Total pending amount for credits you gave (money owed to you).
  Future<double> getTotalPendingGiven();

  /// Total pending for credits you received (money you owe).
  Future<double> getTotalPendingReceived();

  /// Personal total pending given (no business context).
  Future<double> getPersonalTotalPendingGiven();

  /// Party-wise credit summaries.
  Future<List<PartyCreditSummary>> getPartySummaries();

  /// Distinct party names for autocomplete.
  Future<List<String>> getPartyNames();

  /// Insert a new credit entry. Returns the row ID.
  Future<int> insert(Credit credit);

  /// Update an existing credit entry.
  Future<void> update(Credit credit);

  /// Soft-delete a credit entry.
  Future<void> delete(int id);

  /// Record a payment against a credit, updating paid/pending amounts.
  Future<void> recordPayment(int creditId, double amount);
}
