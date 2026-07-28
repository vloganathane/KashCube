import '../../data/models/product_group.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/product_group_repository.dart';

class ProductGroupRepositoryImpl implements ProductGroupRepository {
  ProductGroupRepositoryImpl({this.contextId});

  final _dbHelper = DatabaseHelper.instance;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx =>
      contextId == null ? 'context_id IS NULL' : 'context_id = $contextId';

  @override
  Future<List<ProductGroup>> getAll({bool activeOnly = true}) async {
    final db = await _dbHelper.database;

    final conditions = <String>[_ctx];
    if (activeOnly) conditions.add('deleted_at IS NULL');

    final where = 'WHERE ${conditions.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT * FROM product_groups
      $where
      ORDER BY name COLLATE NOCASE
    ''');

    return rows.map(ProductGroup.fromMap).toList();
  }

  @override
  Future<ProductGroup?> getById(int id) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery(
      '''
      SELECT * FROM product_groups
      WHERE id = ? AND $_ctx
    ''',
      [id],
    );

    return rows.isEmpty ? null : ProductGroup.fromMap(rows.first);
  }

  @override
  Future<int> insert(ProductGroup group) async {
    final db = await _dbHelper.database;
    final id = await db.insert('product_groups', group.toMap());
    _dbHelper.notifyChange('product_groups');
    return id;
  }

  @override
  Future<void> update(ProductGroup group) async {
    final db = await _dbHelper.database;
    await db.update(
      'product_groups',
      group.toMap(),
      where: 'id = ?',
      whereArgs: [group.id],
    );
    _dbHelper.notifyChange('product_groups');
  }

  @override
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.update(
      'product_groups',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    _dbHelper.notifyChange('product_groups');
  }
}
