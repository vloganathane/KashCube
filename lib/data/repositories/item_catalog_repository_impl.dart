import '../../data/models/item_catalog.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/item_catalog_repository.dart';

class ItemCatalogRepositoryImpl implements ItemCatalogRepository {
  final _dbHelper = DatabaseHelper.instance;

  @override
  Future<List<ItemCatalog>> getAll({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final where = activeOnly ? 'WHERE is_active = 1' : '';
    final rows = await db.rawQuery(
        'SELECT * FROM item_catalog $where ORDER BY name COLLATE NOCASE');
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
}
