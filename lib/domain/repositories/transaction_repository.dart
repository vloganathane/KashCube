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

  /// Get transactions for a category within a date range.
  Future<List<Transaction>> getByCategoryInRange(
    String category,
    DateTime start,
    DateTime end,
  );

  /// Get transactions by type (income/expense).
  Future<List<Transaction>> getByType(TransactionType type, {int? limit});

  /// Search transactions by party name or notes.
  Future<List<Transaction>> search(String query);

  /// Get total income for a date range, optionally filtered by mode.
  Future<double> getTotalIncome(DateTime start, DateTime end, {String? mode});

  /// Get total expense for a date range, optionally filtered by mode.
  Future<double> getTotalExpense(DateTime start, DateTime end, {String? mode});

  /// Get category-wise spending summary for a date range.
  Future<Map<String, double>> getCategorySummary(DateTime start, DateTime end, {String? mode});

  /// Get category-wise income summary for a date range.
  Future<Map<String, double>> getIncomeByCategorySummary(
      DateTime start, DateTime end, {String? mode});

  /// Get category-wise expense summary for a date range.
  Future<Map<String, double>> getExpenseByCategorySummary(
      DateTime start, DateTime end, {String? mode});

  /// Get daily totals for a date range (for trend charts).
  Future<List<DailyTotal>> getDailyTotals(DateTime start, DateTime end, {String? mode});

  /// Get monthly totals for the last N months.
  Future<List<MonthlyTotal>> getMonthlyTotals({int months = 6, String? mode});

  /// Get top parties by transaction amount for a date range.
  Future<List<PartyTotal>> getTopParties(
    DateTime start,
    DateTime end, {
    int limit = 10,
    String? mode,
  });

  /// Check if a transaction with this dedupe hash already exists.
  Future<bool> existsByDedupeHash(String hash);

  /// Get recent transactions (for home screen).
  Future<List<Transaction>> getRecent({int limit = 10});

  /// Get party-level ledger summaries (lent/borrowed/invested grouped by party).
  Future<List<LedgerPartyEntry>> getPartyLedgerSummaries();

  /// Get all ledger transactions for a specific party.
  Future<List<Transaction>> getTransactionsByParty(String partyName);

  /// Count transactions linked to a party by ID ([party_id]). P1.2
  Future<int> countByPartyId(int partyId);

  /// All transactions linked to a party by ID. P1.2
  Future<List<Transaction>> getByPartyId(int partyId);

  /// Get total outstanding lent amount (lent - received_back).
  Future<double> getTotalOutstandingLent();

  /// Get total outstanding borrowed amount (borrowed - paid_back).
  Future<double> getTotalOutstandingBorrowed();

  /// Get total amount invested within a date range (type = 'invested').
  Future<double> getTotalInvested(DateTime start, DateTime end);

  /// Get total amount redeemed within a date range (type = 'redeemed').
  Future<double> getTotalRedeemed(DateTime start, DateTime end);

  /// Get top [limit] transactions by amount within [start]–[end], excluding transfers.
  Future<List<Transaction>> getTopByAmount(
    DateTime start,
    DateTime end, {
    int limit = 5,
  });

  /// Get income and expense totals grouped by payment method for a date range.
  Future<Map<String, ({double income, double expense})>> getByPaymentMethod(
    DateTime start,
    DateTime end, {
    String? mode,
  });
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
    this.income = 0,
    this.expense = 0,
  });
  final String partyName;
  final double totalAmount;
  final int transactionCount;
  /// Total income received from this party in the period.
  final double income;
  /// Total expenses paid to this party in the period.
  final double expense;
}

/// Aggregated ledger (khata) position for a single party.
///
/// Covers ALL transaction types that reference a party — not just
/// lending/borrowing.  Income + expense with a party are now first-class
/// citizens so the Ledger screen can render a full T-account khata.
class LedgerPartyEntry {
  const LedgerPartyEntry({
    required this.partyName,
    required this.totalLent,
    required this.totalBorrowed,
    required this.totalReceivedBack,
    required this.totalPaidBack,
    required this.totalInvested,
    required this.totalRedeemed,
    required this.totalIncome,
    required this.totalExpense,
    required this.transactionCount,
    this.personalCount = 0,
    this.businessCount = 0,
    this.lastTransactionDate,
    this.partyType = 'person',
  });

  final String partyName;

  // ── Lending / borrowing ─────────────────────────────────────────────────
  final double totalLent;
  final double totalBorrowed;
  final double totalReceivedBack;
  final double totalPaidBack;

  // ── Investments ─────────────────────────────────────────────────────────
  final double totalInvested;
  final double totalRedeemed;

  // ── Regular transactions with this party ────────────────────────────────
  /// Money received FROM this party (salary, rent, freelance, etc.)
  final double totalIncome;
  /// Money paid TO this party (bills, services, purchases, etc.)
  final double totalExpense;

  final int transactionCount;
  /// Number of personal-mode transactions with this party.
  final int personalCount;
  /// Number of business-mode transactions with this party.
  final int businessCount;
  final DateTime? lastTransactionDate;
  /// 'person' or 'vendor' — sourced from the parties table.
  final String partyType;

  // ── Computed balances ────────────────────────────────────────────────────

  /// Outstanding lent net (lent - received_back).  Positive = they owe you.
  double get netLendingBalance => totalLent - totalReceivedBack;

  /// Outstanding borrowed net (borrowed - paid_back).  Positive = you owe them.
  double get netBorrowingBalance => totalBorrowed - totalPaidBack;

  /// Net money-owed balance: positive = they owe you; negative = you owe them.
  /// Only counts lent/borrowed obligations (not regular income/expense).
  double get netBalance => netLendingBalance - netBorrowingBalance;

  /// Unredeemed investment amount with this party/institution.
  double get netInvestment => totalInvested - totalRedeemed;

  /// True when there are no outstanding obligations (lent/borrowed/invested).
  bool get isCleared => netBalance.abs() < 0.01 && netInvestment.abs() < 0.01;

  /// True when there is any outstanding money-owed obligation.
  bool get hasOutstanding => !isCleared;

  /// True when there are regular income/expense transactions with this party.
  bool get hasRegularActivity => totalIncome > 0 || totalExpense > 0;

  /// Whether this party has only personal transactions.
  bool get isPersonalOnly => personalCount > 0 && businessCount == 0;

  /// Whether this party has only business transactions.
  bool get isBusinessOnly => businessCount > 0 && personalCount == 0;

  /// Whether this party has both personal and business transactions.
  bool get isMixed => personalCount > 0 && businessCount > 0;
}
