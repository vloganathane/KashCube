import '../models/transaction.dart';
import '../services/database_helper.dart';

/// Provides smart suggestions based on transaction history.
///
/// Looks at past transactions with the same party/merchant name to
/// auto-suggest category, payment method, and amount.
class SuggestionService {
  SuggestionService._();
  static final SuggestionService instance = SuggestionService._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Get suggestion based on a party/merchant name.
  ///
  /// Looks at the most recent transactions to this party and returns
  /// the most commonly used category and payment method.
  Future<TransactionSuggestion?> suggestForParty(String partyName) async {
    if (partyName.trim().isEmpty) return null;

    final db = await _dbHelper.database;
    final pattern = '%${partyName.trim()}%';

    // Get recent transactions to this party (max 10)
    final rows = await db.query(
      'transactions',
      where: 'deleted_at IS NULL AND party_name LIKE ?',
      whereArgs: [pattern],
      orderBy: 'date DESC',
      limit: 10,
    );

    if (rows.isEmpty) return null;

    final transactions = rows.map((r) => Transaction.fromMap(r)).toList();

    // Find most common category
    final categoryFrequency = <String, int>{};
    for (final txn in transactions) {
      categoryFrequency[txn.category] =
          (categoryFrequency[txn.category] ?? 0) + 1;
    }
    final bestCategory = categoryFrequency.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    // Find most common payment method
    final methodFrequency = <PaymentMethod, int>{};
    for (final txn in transactions) {
      methodFrequency[txn.paymentMethod] =
          (methodFrequency[txn.paymentMethod] ?? 0) + 1;
    }
    final bestMethod = methodFrequency.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    // Find most common mode
    final modeFrequency = <TransactionMode, int>{};
    for (final txn in transactions) {
      modeFrequency[txn.mode] = (modeFrequency[txn.mode] ?? 0) + 1;
    }
    final bestMode = modeFrequency.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    // Last used amount
    final lastAmount = transactions.first.amount;

    // Average amount
    final avgAmount =
        transactions.map((t) => t.amount).reduce((a, b) => a + b) /
            transactions.length;

    return TransactionSuggestion(
      category: bestCategory,
      paymentMethod: bestMethod,
      mode: bestMode,
      lastAmount: lastAmount,
      averageAmount: avgAmount,
      transactionCount: transactions.length,
    );
  }

  /// Get a list of known party names for autocomplete.
  ///
  /// Returns distinct party names sorted by frequency (most used first).
  Future<List<String>> getKnownPartyNames({int limit = 50}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT party_name, COUNT(*) as cnt '
      'FROM transactions '
      'WHERE deleted_at IS NULL AND party_name IS NOT NULL AND party_name != "" '
      'GROUP BY party_name '
      'ORDER BY cnt DESC '
      'LIMIT ?',
      [limit],
    );

    return rows.map((r) => r['party_name'] as String).toList();
  }
}

/// A suggestion for pre-filling a transaction based on history.
class TransactionSuggestion {
  const TransactionSuggestion({
    required this.category,
    required this.paymentMethod,
    required this.mode,
    required this.lastAmount,
    required this.averageAmount,
    required this.transactionCount,
  });

  /// Most frequently used category for this party.
  final String category;

  /// Most frequently used payment method for this party.
  final PaymentMethod paymentMethod;

  /// Most frequently used mode (personal/business) for this party.
  final TransactionMode mode;

  /// Amount from the most recent transaction.
  final double lastAmount;

  /// Average amount across historical transactions.
  final double averageAmount;

  /// Number of past transactions with this party.
  final int transactionCount;
}
