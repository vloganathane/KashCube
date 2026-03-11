import 'package:sqflite/sqflite.dart';

import '../../data/models/item_catalog.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/item_catalog_repository.dart';

class ItemCatalogRepositoryImpl implements ItemCatalogRepository {
  final _dbHelper = DatabaseHelper.instance;

  /// Columns from [item_catalog] that are not overridden by [item_stock].
  static const _catalogCols = '''
    ic.id, ic.name, ic.description, ic.sku, ic.category, ic.unit,
    ic.unit_price, ic.tax_pct, ic.hsn_code, ic.hsn_or_sac,
    ic.is_favorite, ic.is_active, ic.last_used_at, ic.usage_count,
    ic.duration_minutes, ic.is_bookable, ic.business_id,
    ic.created_at, ic.updated_at
  ''';

  @override
  Future<List<ItemCatalog>> getAll({
    bool activeOnly = true,
    int? businessId,
    ItemCategory? category,
  }) async {
    final db = await _dbHelper.database;

    final conditions = <String>[];
    final args = <dynamic>[];

    if (activeOnly) conditions.add('ic.is_active = 1');

    if (category != null) {
      conditions.add('ic.category = ?');
      args.add(category.name);
    }

    final where =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    const orderBy = '''
      ORDER BY
        ic.is_favorite DESC,
        ic.last_used_at DESC NULLS LAST,
        ic.usage_count DESC,
        ic.name COLLATE NOCASE
    ''';

    if (businessId != null) {
      // Return per-business stock values via LEFT JOIN so that items not yet
      // in item_stock (not tracked for this business) still appear with
      // default zeros — the COALESCE falls back to the item_catalog defaults.
      final rows = await db.rawQuery(
        '''
        SELECT
          $_catalogCols,
          COALESCE(ist.track_inventory, ic.track_inventory)     AS track_inventory,
          COALESCE(ist.stock_qty,       ic.stock_qty)           AS stock_qty,
          COALESCE(ist.low_stock_threshold, ic.low_stock_threshold)
                                                                AS low_stock_threshold
        FROM item_catalog ic
        LEFT JOIN item_stock ist
          ON ist.item_id = ic.id AND ist.business_id = ?
        $where
        $orderBy
        ''',
        [businessId, ...args],
      );
      return rows.map(ItemCatalog.fromMap).toList();
    }

    // No business context — plain catalog list (no stock overlay).
    final rows = await db.rawQuery(
      'SELECT * FROM item_catalog $where $orderBy',
      args,
    );
    return rows.map(ItemCatalog.fromMap).toList();
  }

  @override
  Future<ItemCatalog?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('item_catalog', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ItemCatalog.fromMap(rows.first);
  }

  @override
  Future<int> insert(ItemCatalog item, {int? activeBusinessId}) async {
    final db = await _dbHelper.database;
    final id = await db.insert('item_catalog', item.toMap());
    if (activeBusinessId != null) {
      await _upsertItemStock(
        db,
        businessId: activeBusinessId,
        itemId: id,
        trackInventory: item.trackInventory,
        lowStockThreshold: item.lowStockThreshold,
      );
    }
    return id;
  }

  @override
  Future<void> update(ItemCatalog item, {int? activeBusinessId}) async {
    final db = await _dbHelper.database;
    await db.update('item_catalog', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
    if (activeBusinessId != null && item.id != null) {
      await _upsertItemStock(
        db,
        businessId: activeBusinessId,
        itemId: item.id!,
        trackInventory: item.trackInventory,
        lowStockThreshold: item.lowStockThreshold,
      );
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    // Soft-delete: mark inactive
    await db.update('item_catalog', {'is_active': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> trackUsage(int itemId) async {
    final db = await _dbHelper.database;
    await db.rawUpdate('''
      UPDATE item_catalog
      SET usage_count = usage_count + 1,
          last_used_at = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), itemId]);
  }

  @override
  Future<String> generateNextSku(ItemCategory category) async {
    final db = await _dbHelper.database;
    final prefix = _getCategoryPrefix(category);

    final result = await db.rawQuery('''
      SELECT sku FROM item_catalog
      WHERE sku LIKE ? AND is_active = 1
      ORDER BY sku DESC
      LIMIT 1
    ''', ['$prefix-%']);

    int nextNumber = 1;
    if (result.isNotEmpty && result.first['sku'] != null) {
      final lastSku = result.first['sku'] as String;
      final parts = lastSku.split('-');
      if (parts.length == 2) {
        nextNumber = (int.tryParse(parts[1]) ?? 0) + 1;
      }
    }

    return '$prefix-${nextNumber.toString().padLeft(3, '0')}';
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Upserts the [item_stock] row for ([businessId], [itemId]).
  ///
  /// Only [track_inventory] and [low_stock_threshold] are touched — stock_qty
  /// is never reset here (it is managed exclusively by [InventoryService]).
  Future<void> _upsertItemStock(
    Database db, {
    required int businessId,
    required int itemId,
    required bool trackInventory,
    required double lowStockThreshold,
  }) async {
    await db.rawInsert(
      '''
      INSERT INTO item_stock
        (business_id, item_id, track_inventory, low_stock_threshold, stock_qty)
      VALUES (?, ?, ?, ?, 0)
      ON CONFLICT(business_id, item_id) DO UPDATE SET
        track_inventory     = excluded.track_inventory,
        low_stock_threshold = excluded.low_stock_threshold
      ''',
      [businessId, itemId, trackInventory ? 1 : 0, lowStockThreshold],
    );
  }

  String _getCategoryPrefix(ItemCategory category) {
    switch (category) {
      case ItemCategory.product:
        return 'PROD';
      case ItemCategory.service:
        return 'SERV';
      case ItemCategory.material:
        return 'MATL';
      case ItemCategory.labor:
        return 'LABR';
      case ItemCategory.equipment:
        return 'EQUP';
      case ItemCategory.other:
        return 'OTHR';
    }
  }
}
