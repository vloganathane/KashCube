import '../../data/models/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Encapsulates the creation of a new [Transaction].
///
/// Centralises validation and the insert call so it can be reused by multiple
/// presentation entry points (Add Transaction screen, SMS confirmation sheet,
/// recurring transaction auto-creation) without repeating logic.
class CreateTransactionUseCase {
  const CreateTransactionUseCase({
    required TransactionRepository transactionRepository,
  }) : _repo = transactionRepository;

  final TransactionRepository _repo;

  /// Validates [transaction] and persists it.
  ///
  /// Throws [ArgumentError] if the transaction amount is non-positive or if
  /// the category is empty — these invariants must hold for the DB to be
  /// meaningful.
  ///
  /// Returns the newly assigned row ID on success.
  Future<int> call(Transaction transaction) async {
    if (transaction.amount <= 0) {
      throw ArgumentError.value(
        transaction.amount,
        'amount',
        'Transaction amount must be greater than zero.',
      );
    }
    if (transaction.category.trim().isEmpty) {
      throw ArgumentError.value(
        transaction.category,
        'category',
        'Transaction category must not be empty.',
      );
    }
    return _repo.insert(transaction);
  }
}
