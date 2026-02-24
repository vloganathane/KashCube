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

/// Provider for overdue credits list.
final overdueCreditsProvider = FutureProvider<List<CreditRecord>>((ref) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getOverdue();
});

/// Provider for cleared credits list.
final clearedCreditsProvider = FutureProvider<List<CreditRecord>>((ref) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getCleared();
});

/// Provider for customer summaries.
final customerSummariesProvider =
    FutureProvider<List<CustomerCreditSummary>>((ref) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getCustomerSummaries();
});

/// Provider for credits by customer name.
final creditsByCustomerProvider =
    FutureProvider.family<List<CreditRecord>, String>((ref, customerName) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getByCustomer(customerName);
});

/// Provider for a single customer's credit summary.
final customerSummaryProvider =
    FutureProvider.family<CustomerCreditSummary?, String>((ref, customerName) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getCustomerSummary(customerName);
});

/// Provider for payments on a specific credit record.
final creditPaymentsProvider =
    FutureProvider.family<List<CreditPayment>, int>((ref, creditId) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getPaymentsForCredit(creditId);
});

/// Provider for a single credit record by ID.
final creditByIdProvider =
    FutureProvider.family<CreditRecord?, int>((ref, creditId) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getById(creditId);
});

/// Provider for known customer names (for autocomplete).
final creditCustomerNamesProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.read(creditRepositoryProvider);
  return repo.getCustomerNames();
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

  Future<void> recordPayment(
    int creditId,
    double amount, {
    String? paymentMethod,
    int? transactionId,
    String? notes,
  }) async {
    try {
      await _repository.recordPayment(
        creditId,
        amount,
        paymentMethod: paymentMethod,
        transactionId: transactionId,
        notes: notes,
      );
      await loadPending();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
