import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/loan.dart';
import '../../data/repositories/loan_repository_impl.dart';
import '../../domain/repositories/loan_repository.dart';

/// Repository provider for loans.
final loanRepositoryProvider = Provider<LoanRepository>(
  (ref) => LoanRepositoryImpl(),
);

/// Active (not cleared) loans.
final activeLoansProvider =
    StateNotifierProvider<LoansNotifier, AsyncValue<List<Loan>>>(
  (ref) => LoansNotifier(ref.read(loanRepositoryProvider)),
);

class LoansNotifier extends StateNotifier<AsyncValue<List<Loan>>> {
  final LoanRepository _repo;

  LoansNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadActive();
  }

  Future<void> loadActive() async {
    try {
      final loans = await _repo.getActive();
      state = AsyncValue.data(loans);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addLoan(Loan loan) async {
    await _repo.insert(loan);
    await loadActive();
  }

  Future<void> updateLoan(Loan loan) async {
    await _repo.update(loan);
    await loadActive();
  }

  Future<void> deleteLoan(int id) async {
    await _repo.delete(id);
    await loadActive();
  }

  Future<void> recordPayment(int loanId, double amount) async {
    await _repo.recordPayment(loanId, amount);
    await loadActive();
  }
}

/// Loan by ID (family provider).
final loanByIdProvider =
    FutureProvider.family<Loan?, int>((ref, id) async {
  final repo = ref.read(loanRepositoryProvider);
  return repo.getById(id);
});

/// Total pending loan amount.
final totalPendingLoanProvider = FutureProvider<double>((ref) async {
  final repo = ref.read(loanRepositoryProvider);
  return repo.getTotalPending();
});

/// Cleared loans.
final clearedLoansProvider = FutureProvider<List<Loan>>((ref) async {
  final repo = ref.read(loanRepositoryProvider);
  return repo.getCleared();
});

/// Overdue loans.
final overdueLoansProvider = FutureProvider<List<Loan>>((ref) async {
  final repo = ref.read(loanRepositoryProvider);
  return repo.getOverdue();
});
