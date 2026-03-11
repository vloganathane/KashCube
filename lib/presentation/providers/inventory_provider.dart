import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/item_catalog.dart';
import '../../data/models/stock_movement.dart';
import '../../data/services/inventory_service.dart';
import 'business_provider.dart';

final _inventoryService = InventoryService.instance;

// ── Inventory list ────────────────────────────────────────────────────────────

class InventoryNotifier
    extends StateNotifier<AsyncValue<List<ItemCatalog>>> {
  InventoryNotifier(this._businessId)
      : super(const AsyncValue.loading()) {
    load();
  }

  final int? _businessId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _inventoryService.getTrackedItems(businessId: _businessId),
    );
  }

  Future<void> addStock(int itemId, double qty, {String? notes}) async {
    await _inventoryService.addStock(itemId, qty,
        notes: notes, businessId: _businessId);
    await load();
  }

  Future<void> deductStock(int itemId, double qty, {String? notes}) async {
    await _inventoryService.deductStock(itemId, qty,
        notes: notes, businessId: _businessId);
    await load();
  }

  Future<void> setStock(int itemId, double qty, {String? notes}) async {
    await _inventoryService.setStock(itemId, qty,
        notes: notes, businessId: _businessId);
    await load();
  }

  Future<void> setTrackInventory(int itemId, {required bool track}) async {
    await _inventoryService.setTrackInventory(itemId,
        track: track, businessId: _businessId);
    await load();
  }

  Future<void> setThreshold(int itemId, double threshold) async {
    await _inventoryService.setLowStockThreshold(itemId, threshold,
        businessId: _businessId);
    await load();
  }
}

final inventoryProvider = StateNotifierProvider.autoDispose
    .family<InventoryNotifier, AsyncValue<List<ItemCatalog>>, int?>(
  (ref, businessId) => InventoryNotifier(businessId),
);

// ── Low-stock items ────────────────────────────────────────────────────────────

final lowStockItemsProvider =
    FutureProvider.autoDispose.family<List<ItemCatalog>, int?>(
  (ref, businessId) => _inventoryService.getLowStockItems(businessId: businessId),
);

final lowStockCountProvider = Provider.autoDispose.family<int, int?>(
  (ref, businessId) =>
      ref.watch(lowStockItemsProvider(businessId)).valueOrNull?.length ?? 0,
);

// ── Stock movements for an item ───────────────────────────────────────────────

final stockMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, int>((ref, itemId) {
  return _inventoryService.getMovementsForItem(itemId);
});

// ── Helper: active business id ────────────────────────────────────────────────

final activeBusinessIdProvider = Provider.autoDispose<int?>((ref) {
  return ref.watch(activeBusinessProvider)?.id;
});
