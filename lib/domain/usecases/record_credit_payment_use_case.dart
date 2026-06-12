import '../repositories/credit_repository.dart';

/// Records a partial or full payment against an existing credit (udhar) entry.
///
/// Validates that the payment amount is positive and does not exceed the
/// outstanding balance before delegating to [CreditRepository.recordPayment].
/// Centralises these checks so they are not repeated across screens.
class RecordCreditPaymentUseCase {
  const RecordCreditPaymentUseCase({required CreditRepository creditRepository})
    : _repo = creditRepository;

  final CreditRepository _repo;

  /// Records a [amount] payment against credit [creditId].
  ///
  /// Throws [ArgumentError] when:
  /// - [creditId] ≤ 0 (not a persisted record),
  /// - [amount] ≤ 0 (payment must be positive),
  /// - [amount] > [outstandingBalance] (over-payment not allowed here; the
  ///   caller should mark the credit cleared instead).
  Future<void> call({
    required int creditId,
    required double amount,
    required double outstandingBalance,
  }) async {
    if (creditId <= 0) {
      throw ArgumentError.value(
        creditId,
        'creditId',
        'Must reference a saved credit.',
      );
    }
    if (amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Payment amount must be positive.',
      );
    }
    if (amount > outstandingBalance) {
      throw ArgumentError(
        'Payment amount ($amount) exceeds outstanding balance ($outstandingBalance). '
        'Use the clear-credit flow to settle in full.',
      );
    }
    await _repo.recordPayment(creditId, amount);
  }
}
