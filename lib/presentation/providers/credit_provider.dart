import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/credit_record.dart';
import '../../data/repositories/credit_repository_impl.dart';
import '../../domain/repositories/credit_repository.dart';

/// Provider for the credit repository instance.
final creditRepositoryProvider = Provider<CreditRepository>(
  (ref) => CreditRepositoryImpl(),
);

/// Provider for all pending credits.
final pendingCreditsProvider =
    StateNotifierProvider<CreditsNotifier, AsyncValue<List<CreditRecord>>>(
  (ref) => CreditsNotifier(ref.read(creditRepositoryProvider)),
);

/// Provider for total pending credit amount.
final totalPendingCreditProvider = FutureProvider<double>((ref) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getTotalPending();
});

/// Provider for total overdue credit amount.
final totalOverdueCreditProvider = FutureProvider<double>((ref) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getTotalOverdue();
});

/// Manages credit records state.
class CreditsNotifier extends StateNotifier<AsyncValue<List<CreditRecord>>> {
  final CreditRepository _repository;

  CreditsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadPending();
  }

  Future<void> loadPending() async {
    state = const AsyncValue.loading();
    try {
      final credits = await _repository.getPending();
      state = AsyncValue.data(credits);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadAll() async {
    state = const AsyncValue.loading();
    try {
      final credits = await _repository.getAll();
      state = AsyncValue.data(credits);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addCredit(CreditRecord credit) async {
    try {
      await _repository.insert(credit);
      await loadPending();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateCredit(CreditRecord credit) async {
    try {
      await _repository.update(credit);
      await loadPending();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteCredit(int id) async {
    try {
      await _repository.delete(id);
      await loadPending();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> recordPayment(int creditId, double amount) async {
    try {
      await _repository.recordPayment(creditId, amount);
      await loadPending();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
