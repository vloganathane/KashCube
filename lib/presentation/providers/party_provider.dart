import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/party.dart';
import '../../data/repositories/party_repository_impl.dart';
import '../../domain/repositories/party_repository.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final partyRepositoryProvider = Provider<PartyRepository>(
  (_) => PartyRepositoryImpl(),
);

// ---------------------------------------------------------------------------
// Party list — CRUD
// ---------------------------------------------------------------------------

final partiesProvider =
    StateNotifierProvider<PartiesNotifier, AsyncValue<List<Party>>>(
  (ref) => PartiesNotifier(ref.read(partyRepositoryProvider)),
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
