import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/delivery_challan.dart';
import '../../data/repositories/delivery_challan_repository_impl.dart';
import '../../data/services/inventory_service.dart';
import '../../data/services/lot_allocation_service.dart';
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
    final id = await _repo.insert(challan, challan.items);
    // Deduct aggregate stock + allocate lots (FEFO) on every DC save.
    for (final item in challan.items) {
      if (item.catalogItemId != null && item.qty > 0) {
        await InventoryService.instance.deductStock(
          item.catalogItemId!,
          item.qty,
          notes: 'DC ${challan.challanNo}',
          referenceId: id,
          referenceType: 'challan',
          businessId: challan.businessId,
        );
        await LotAllocationService.instance.allocateFefo(
          businessId: challan.businessId ?? 0,
          itemId: item.catalogItemId!,
          qty: item.qty,
          referenceType: 'challan',
          referenceId: id,
          referenceLineId: item.id,
        );
      }
    }
    await _load();
    return challan.copyWith(id: id);
  }

  Future<DeliveryChallan> edit(DeliveryChallan challan) async {
    // Reverse previous lot + aggregate stock movements, then re-apply new items.
    if (challan.id != null) {
      await LotAllocationService.instance
          .reverseLotMovements('challan', challan.id!);
      await InventoryService.instance
          .reverseMovementsFor('challan', challan.id!);
    }
    await _repo.update(challan, challan.items);
    for (final item in challan.items) {
      if (item.catalogItemId != null && item.qty > 0) {
        await InventoryService.instance.deductStock(
          item.catalogItemId!,
          item.qty,
          notes: 'DC ${challan.challanNo} (edited)',
          referenceId: challan.id,
          referenceType: 'challan',
          businessId: challan.businessId,
        );
        await LotAllocationService.instance.allocateFefo(
          businessId: challan.businessId ?? 0,
          itemId: item.catalogItemId!,
          qty: item.qty,
          referenceType: 'challan',
          referenceId: challan.id ?? 0,
          referenceLineId: item.id,
        );
      }
    }
    await _load();
    return challan;
  }

  Future<void> remove(int id) async {
    // Reverse lot movements + aggregate stock before deleting.
    await LotAllocationService.instance.reverseLotMovements('challan', id);
    await InventoryService.instance.reverseMovementsFor('challan', id);
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

/// Finds the Delivery Challan that was converted into a given invoice.
/// Uses the in-memory list so no extra DB round-trip is needed.
final challanByInvoiceIdProvider =
    Provider.family<DeliveryChallan?, int>((ref, invoiceId) {
  final all =
      ref.watch(challansProvider).whenOrNull(data: (list) => list) ?? [];
  try {
    return all.firstWhere((c) => c.convertedInvoiceId == invoiceId);
  } catch (_) {
    return null;
  }
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

/// All delivery challans for a given party name (used by Party Document Ledger).
final challansByCustomerProvider =
    FutureProvider.family<List<DeliveryChallan>, String>((ref, customerName) async {
  return ref.read(deliveryChallanRepositoryProvider).getByCustomer(customerName);
});
