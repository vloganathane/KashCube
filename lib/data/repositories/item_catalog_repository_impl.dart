import '../../data/models/item_catalog.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/item_catalog_repository.dart';

class ItemCatalogRepositoryImpl implements ItemCatalogRepository {
  final _dbHelper = DatabaseHelper.instance;

  @override
  Future<List<ItemCatalog>> getAll({
    bool activeOnly = true,
    int? businessId,
    ItemCategory? category,
  }) async {
    final db = await _dbHelper.database;
    
    // Build WHERE clause
    final conditions = <String>[];
    final args = <dynamic>[];
    
    if (activeOnly) {
      conditions.add('is_active = 1');
    }
    
    if (businessId != null) {
      conditions.add('(business_id = ? OR business_id IS NULL)');
      args.add(businessId);
    }
    
    if (category != null) {
      conditions.add('category = ?');
      args.add(category.name);
    }
    
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    
    // Smart sorting: favorites → recently used → most used → alphabetically
    const orderBy = '''
      ORDER BY 
        is_favorite DESC, 
        last_used_at DESC NULLS LAST, 
        usage_count DESC, 
        name COLLATE NOCASE
    ''';
    
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
  Future<int> insert(ItemCatalog item) async {
    final db = await _dbHelper.database;
    return db.insert('item_catalog', item.toMap());
  }

  @override
  Future<void> update(ItemCatalog item) async {
    final db = await _dbHelper.database;
    await db.update('item_catalog', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
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
    
    // Find highest existing number for this category prefix
    final result = await db.rawQuery('''
      SELECT sku FROM item_catalog 
      WHERE sku LIKE ? AND is_active = 1 
      ORDER BY sku DESC 
      LIMIT 1
    ''', ['$prefix-%']);
    
    int nextNumber = 1;
    if (result.isNotEmpty && result.first['sku'] != null) {
      final lastSku = result.first['sku'] as String;
      // Extract number from "PREFIX-NNN" format
      final parts = lastSku.split('-');
      if (parts.length == 2) {
        nextNumber = (int.tryParse(parts[1]) ?? 0) + 1;
      }
    }
    
    return '$prefix-${nextNumber.toString().padLeft(3, '0')}';
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
