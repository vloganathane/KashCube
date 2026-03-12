import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/credit.dart';
import '../../data/repositories/credit_repository_impl.dart';
import '../../domain/repositories/credit_repository.dart';
import 'context_provider.dart';

/// Repository provider for credits / udhar.
/// Rebuilds automatically when [activeContextProvider] changes.
final creditRepositoryProvider = Provider<CreditRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return CreditRepositoryImpl(null, contextId);
  },
);

// ── All active credits ─────────────────────────────────────────────────────

/// All active (not cleared, not deleted) credits.
final activeCreditsProvider =
    StateNotifierProvider<CreditsNotifier, AsyncValue<List<Credit>>>(
  (ref) => CreditsNotifier(ref.watch(creditRepositoryProvider)),
);

class CreditsNotifier extends StateNotifier<AsyncValue<List<Credit>>> {
  final CreditRepository _repo;

  CreditsNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadActive();
  }

  Future<void> loadActive() async {
    try {
      final credits = await _repo.getActive();
      state = AsyncValue.data(credits);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addCredit(Credit credit) async {
    await _repo.insert(credit);
    await loadActive();
  }

  Future<void> updateCredit(Credit credit) async {
    await _repo.update(credit);
    await loadActive();
  }

  Future<void> deleteCredit(int id) async {
    await _repo.delete(id);
    await loadActive();
  }

  Future<void> recordPayment(int creditId, double amount) async {
    await _repo.recordPayment(creditId, amount);
    await loadActive();
  }
}

// ── Personal credits (no business context) ────────────────────────────────

/// Active personal credits — given (others owe you) and received (you owe others).
/// `null` businessId only. Used for home screen alerts and personal Action Center.
final personalCreditsProvider = FutureProvider<List<Credit>>((ref) {
  return ref.read(creditRepositoryProvider).getPersonal();
});

/// Total outstanding amount you are owed personally (given, not cleared).
final personalCreditsPendingGivenProvider = FutureProvider<double>((ref) {
  return ref.read(creditRepositoryProvider).getPersonalTotalPendingGiven();
});

// ── Per-party credits ─────────────────────────────────────────────────────

/// Credits for a specific party name (all, not only personal).
/// Used in party detail screen to show credit history.
final partyCreditsProvider =
    FutureProvider.family<List<Credit>, String>((ref, partyName) {
  return ref.read(creditRepositoryProvider).getByPartyName(partyName);
});

// ── Aggregates ─────────────────────────────────────────────────────────────

/// Total outstanding across all credits you gave (business + personal).
final totalCreditsPendingGivenProvider = FutureProvider<double>((ref) {
  return ref.read(creditRepositoryProvider).getTotalPendingGiven();
});

/// Total outstanding across all credits you received (money you owe).
final totalCreditsPendingReceivedProvider = FutureProvider<double>((ref) {
  return ref.read(creditRepositoryProvider).getTotalPendingReceived();
});

/// Party-wise credit summaries for the credits overview screen.
final creditPartySummariesProvider =
    FutureProvider<List<PartyCreditSummary>>((ref) {
  return ref.read(creditRepositoryProvider).getPartySummaries();
});
