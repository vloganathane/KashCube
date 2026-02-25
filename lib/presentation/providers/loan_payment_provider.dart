import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/loan_payment.dart';
import '../../data/repositories/loan_payment_repository_impl.dart';
import '../../domain/repositories/loan_payment_repository.dart';

/// Repository provider for loan payments.
final loanPaymentRepositoryProvider = Provider<LoanPaymentRepository>(
  (ref) => LoanPaymentRepositoryImpl(),
);

/// All payments for a specific loan.
final loanPaymentsProvider =
    FutureProvider.family<List<LoanPayment>, int>((ref, loanId) async {
  final repo = ref.read(loanPaymentRepositoryProvider);
  return repo.getByLoanId(loanId);
});

/// Upcoming (unpaid) payments for a loan.
final upcomingPaymentsProvider =
    FutureProvider.family<List<LoanPayment>, int>((ref, loanId) async {
  final repo = ref.read(loanPaymentRepositoryProvider);
  return repo.getUpcoming(loanId);
});

/// Overdue payments for a loan.
final overduePaymentsProvider =
    FutureProvider.family<List<LoanPayment>, int>((ref, loanId) async {
  final repo = ref.read(loanPaymentRepositoryProvider);
  return repo.getOverdue(loanId);
});

/// Next payment due for a loan.
final nextPaymentProvider =
    FutureProvider.family<LoanPayment?, int>((ref, loanId) async {
  final repo = ref.read(loanPaymentRepositoryProvider);
  return repo.getNextPayment(loanId);
});

/// Map of loanId → next unpaid payment due date, across ALL loans with schedules.
/// Used by upcomingItemsProvider as a fallback when loan.nextEmiDate is null.
final nextPaymentDatesForAllProvider =
    FutureProvider<Map<int, DateTime>>((ref) async {
  final repo = ref.read(loanPaymentRepositoryProvider);
  return repo.getNextPaymentDatesForAll();
});
