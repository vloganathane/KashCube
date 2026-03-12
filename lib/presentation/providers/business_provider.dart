import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/business.dart';
import '../../data/repositories/business_repository_impl.dart';
import '../../domain/repositories/business_repository.dart';
import 'context_provider.dart';

// ── Repository ──────────────────────────────────────────────────────────────────────

final businessRepositoryProvider = Provider<BusinessRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return BusinessRepositoryImpl(contextId: contextId);
  },
);

// ── List of all businesses ────────────────────────────────────────────────────

class BusinessesNotifier
    extends StateNotifier<AsyncValue<List<Business>>> {
  BusinessesNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final BusinessRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getAll());
  }

  Future<void> add(Business business, {bool setActive = false}) async {
    await _repo.insert(business, setActive: setActive);
    await load();
  }

  Future<void> edit(Business business) async {
    await _repo.update(business);
    await load();
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    await load();
  }

  Future<void> activate(int id) async {
    await _repo.setActive(id);
    await load();
  }
}

final businessesProvider =
    StateNotifierProvider<BusinessesNotifier, AsyncValue<List<Business>>>(
  (ref) => BusinessesNotifier(ref.read(businessRepositoryProvider)),
);

// ── Active business (convenience) ────────────────────────────────────────────

/// The currently active business profile, or null if none is set.
final activeBusinessProvider = Provider<Business?>((ref) {
  return ref.watch(businessesProvider).whenOrNull(
    data: (list) =>
        list.isEmpty ? null : list.firstWhere((b) => b.isActive, orElse: () => list.first),
  );
});
