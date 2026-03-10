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
    await _inventoryService.addStock(itemId, qty, notes: notes);
    await load();
  }

  Future<void> deductStock(int itemId, double qty, {String? notes}) async {
    await _inventoryService.deductStock(itemId, qty, notes: notes);
    await load();
  }

  Future<void> setStock(int itemId, double qty, {String? notes}) async {
    await _inventoryService.setStock(itemId, qty, notes: notes);
    await load();
  }

  Future<void> setTrackInventory(int itemId, {required bool track}) async {
    await _inventoryService.setTrackInventory(itemId, track: track);
    await load();
  }

  Future<void> setThreshold(int itemId, double threshold) async {
    await _inventoryService.setLowStockThreshold(itemId, threshold);
    await load();
  }
}

final inventoryProvider = StateNotifierProvider.autoDispose<InventoryNotifier,
    AsyncValue<List<ItemCatalog>>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  return InventoryNotifier(businessId);
});

// ── Low-stock items ────────────────────────────────────────────────────────────

final lowStockItemsProvider =
    FutureProvider.autoDispose<List<ItemCatalog>>((ref) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  return _inventoryService.getLowStockItems(businessId: businessId);
});

final lowStockCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(lowStockItemsProvider).valueOrNull?.length ?? 0;
});

// ── Stock movements for an item ───────────────────────────────────────────────

final stockMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, int>((ref, itemId) {
  return _inventoryService.getMovementsForItem(itemId);
});

// ── Helper: active business id ────────────────────────────────────────────────

final activeBusinessIdProvider = Provider.autoDispose<int?>((ref) {
  return ref.watch(activeBusinessProvider)?.id;
});
