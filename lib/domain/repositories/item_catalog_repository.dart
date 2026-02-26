import '../../data/models/item_catalog.dart';

abstract class ItemCatalogRepository {
  Future<List<ItemCatalog>> getAll({
    bool activeOnly = true,
    int? businessId,
    ItemCategory? category,
  });
  Future<ItemCatalog?> getById(int id);
  Future<int> insert(ItemCatalog item);
  Future<void> update(ItemCatalog item);
  Future<void> delete(int id);
  Future<void> trackUsage(int itemId);
  Future<String> generateNextSku(ItemCategory category);
}
