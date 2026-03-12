import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/party.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/party_repository_impl.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/party_repository.dart';
import 'context_provider.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final partyRepositoryProvider = Provider<PartyRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return PartyRepositoryImpl(null, contextId);
  },
);

// ---------------------------------------------------------------------------
// Party list — CRUD
// ---------------------------------------------------------------------------

final partiesProvider =
    StateNotifierProvider<PartiesNotifier, AsyncValue<List<Party>>>(
  (ref) => PartiesNotifier(ref.watch(partyRepositoryProvider)),
);

class PartiesNotifier extends StateNotifier<AsyncValue<List<Party>>> {
  PartiesNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final PartyRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repo.getAll());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Party party) async {
    try {
      final id = await _repo.insert(party);
      final created = party.copyWith(id: id, createdAt: DateTime.now());
      state = state.whenData((list) => [...list, created]
        ..sort((a, b) => a.name.compareTo(b.name)));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Adds a [party] that was already inserted to the DB to the in-memory list.
  /// Used when the form handles the insert itself (add mode with pending addresses).
  void addToState(Party party) {
    state = state.whenData((list) => [...list, party]
      ..sort((a, b) => a.name.compareTo(b.name)));
  }

  Future<void> update(Party party) async {
    try {
      await _repo.update(party);
      state = state.whenData((list) =>
          list.map((p) => p.id == party.id ? party : p).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> remove(int id) async {
    try {
      await _repo.delete(id);
      state = state.whenData(
          (list) => list.where((p) => p.id != id).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markReminderSent(int transactionId) async {
    await _repo.markReminderSent(transactionId);
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

final partySearchQueryProvider = StateProvider<String>((_) => '');

final filteredPartiesProvider = Provider<AsyncValue<List<Party>>>((ref) {
  final parties = ref.watch(partiesProvider);
  final query = ref.watch(partySearchQueryProvider);
  if (query.trim().isEmpty) return parties;
  return parties.whenData((list) {
    final q = query.toLowerCase();
    return list
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.phoneNumber?.contains(q) ?? false))
        .toList();
  });
});

// ---------------------------------------------------------------------------
// Party name autocomplete (used in transaction/credit entry forms)
// ---------------------------------------------------------------------------

final partyNameSuggestionsProvider =
    FutureProvider.family<List<String>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  final repo = ref.read(partyRepositoryProvider);
  final results = await repo.search(query);
  return results.map((p) => p.name).toList();
});

// ---------------------------------------------------------------------------
// Staff — HRMS Phase S1
// ---------------------------------------------------------------------------

/// All active staff parties (partyType == staff), ordered by name.
final staffMembersProvider = FutureProvider<List<Party>>((ref) async {
  final repo = ref.read(partyRepositoryProvider);
  return repo.getStaffMembers();
});

/// Payroll transaction history for a single staff member.
///
/// Pass a record of `(partyId, month, year)` where month/year are the
/// pay period (1-based month). Set month = 0 to load all history.
final staffPayrollProvider =
    FutureProvider.family<List<Transaction>, ({int partyId, int month, int year})>(
  (ref, args) async {
    final repo = TransactionRepositoryImpl();
    return repo.getPayrollHistory(
      staffPartyId: args.partyId,
      month: args.month > 0 ? args.month : null,
      year: args.year > 0 ? args.year : null,
    );
  },
);
