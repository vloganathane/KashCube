import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/delivery_challan.dart';
import '../../data/repositories/delivery_challan_repository_impl.dart';
import '../../domain/repositories/delivery_challan_repository.dart';

// ── Repository ──────────────────────────────────────────────────────────────

final deliveryChallanRepositoryProvider =
    Provider<DeliveryChallanRepository>((ref) {
  return DeliveryChallanRepositoryImpl();
});

// ── Main notifier ────────────────────────────────────────────────────────────

class ChallansNotifier
    extends StateNotifier<AsyncValue<List<DeliveryChallan>>> {
  ChallansNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  final DeliveryChallanRepository _repo;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _repo.getAll();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> invalidate() => _load();

  Future<DeliveryChallan> add(DeliveryChallan challan) async {
    final created = await _repo.insert(challan);
    await _load();
    return created;
  }

  Future<DeliveryChallan> edit(DeliveryChallan challan) async {
    final updated = await _repo.update(challan);
    await _load();
    return updated;
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    await _load();
  }

  Future<void> dispatch(int id, {DateTime? dispatchDate}) async {
    await _repo.markDispatched(id, dispatchDate: dispatchDate);
    await _load();
  }

  Future<void> markReturned(int id) async {
    await _repo.markReturned(id);
    await _load();
  }
}

final challansProvider =
    StateNotifierProvider<ChallansNotifier, AsyncValue<List<DeliveryChallan>>>(
  (ref) => ChallansNotifier(ref.read(deliveryChallanRepositoryProvider)),
);

// ── Single challan ────────────────────────────────────────────────────────────

final challanByIdProvider =
    FutureProvider.family<DeliveryChallan?, int>((ref, id) async {
  ref.watch(challansProvider); // keep up to date when list changes
  return ref.read(deliveryChallanRepositoryProvider).getById(id);
});

// ── Filter ───────────────────────────────────────────────────────────────────

final challanStatusFilterProvider = StateProvider<ChallanStatus?>((ref) => null);

final filteredChallansProvider =
    Provider<AsyncValue<List<DeliveryChallan>>>((ref) {
  final allAsync = ref.watch(challansProvider);
  final filter = ref.watch(challanStatusFilterProvider);
  return allAsync.whenData((list) {
    if (filter == null) return list;
    return list.where((c) => c.status == filter).toList();
  });
});

// ── Summary stats ─────────────────────────────────────────────────────────────

class ChallanSummary {
  const ChallanSummary({
    required this.total,
    required this.dispatched,
    required this.draft,
  });

  final int total;
  final int dispatched;
  final int draft;
}

final challanSummaryProvider = Provider<ChallanSummary>((ref) {
  final all =
      ref.watch(challansProvider).whenOrNull(data: (list) => list) ?? [];
  return ChallanSummary(
    total: all.length,
    dispatched:
        all.where((c) => c.status == ChallanStatus.dispatched).length,
    draft: all.where((c) => c.status == ChallanStatus.draft).length,
  );
});
